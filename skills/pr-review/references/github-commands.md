# GitHub操作のコマンド集

`gh` CLI を使う。`OWNER`、`REPO`、`NUMBER`、`PR_URL` は対象のPRに置き換える。

### GraphQL が使えない環境（クラウド版 Claude Code など）

`gh api graphql` や、内部で GraphQL を使う `gh pr view`・`gh pr checks`・`gh pr list`・`gh pr review`・`gh pr comment`・`gh pr merge`・`gh issue view`・`gh repo view` が `HTTP 403: GitHub GraphQL is not available ...` で失敗する環境がある。その場合は、各章の「GraphQL が使えない環境では」の REST（`gh api repos/...`）の手順を使う。`gh pr diff` と `gh api repos/...` は使える。

- レビュースレッドの一覧と resolve は REST にないため、クラウドのプロキシが提供する CCR ルート（`repos/OWNER/REPO/pulls/NUMBER/ccr/...`）を使う。CCR ルートはクラウドの環境でしか使えない。GraphQL が使える環境では、従来どおり GraphQL を使う。
- `search/issues` などリポジトリの外のパスは使えないことがある。`repos/OWNER/REPO/...` の下のエンドポイントで代替する。

## 目次
1. PRの情報取得
2. レビューの投稿
3. スレッドの取得・返信・resolve
4. issueの確認・issueに対応するPRを探す
5. マージ方式の判定
6. マージ

## 1. PRの情報取得

```bash
gh pr view PR_URL --json number,title,body,author,baseRefName,headRefName,headRefOid,isDraft,state,mergeable,mergeStateStatus,reviewDecision,url
gh pr diff PR_URL
gh pr checks PR_URL          # CIの状態
```

前回確認したSHAからの差分（新しいコミットがあったとき）:

```bash
gh api repos/OWNER/REPO/compare/OLD_SHA...NEW_SHA --jq '.files[] | {filename, status, patch}'
```

force push などで OLD_SHA が履歴から消えている場合は、PR全体の差分で未解決の指摘箇所を確認する。

GraphQL が使えない環境では:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER \
  --jq '{number, title, body, author: .user.login, base: .base.ref, head: .head.ref, headSha: .head.sha, draft, state, merged, mergeable, mergeable_state, url: .html_url}'
# CIの状態（HEAD_SHA は上の headSha）。check run と、コミットステータスの両方を見る
gh api "repos/OWNER/REPO/commits/HEAD_SHA/check-runs?per_page=100" --jq '.check_runs[] | {name, status, conclusion, details_url}'
gh api "repos/OWNER/REPO/commits/HEAD_SHA/status" --jq '.statuses[] | {context, state, target_url}'
```

- `state` は `open` / `closed`。マージ済みは `merged` が `true`。
- `mergeable` は `true`（マージ可能）/ `false`（コンフリクト）/ `null`（GitHubが計算中。少し待って取り直す）。
- `reviewDecision` に相当する値は REST にない。レビューの状態は `gh api repos/OWNER/REPO/pulls/NUMBER/reviews` で見る。
- check run は `status` が `completed` になるまで実行中。`conclusion` が `success`・`skipped`・`neutral` 以外なら失敗として扱う。

言語の判定用に、最近のPRとレビューコメントを見る:

```bash
gh pr list --repo OWNER/REPO --state all --limit 5 --json number,title,body
# GraphQL が使えない環境では
gh api "repos/OWNER/REPO/pulls?state=all&per_page=5" --jq '.[] | {number, title, body}'
```

## 2. レビューの投稿

インラインコメントと全体サマリーを1回のAPI呼び出しで投稿する。JSONをファイルに書いてから渡すと、改行やバッククォートのエスケープで失敗しにくい。

```bash
cat > review.json <<'EOF'
{
  "commit_id": "HEAD_SHA",
  "event": "COMMENT",
  "body": "## レビュー結果\n...\n\n<!-- pr-review -->",
  "comments": [
    {
      "path": "src/foo.py",
      "line": 42,
      "side": "RIGHT",
      "body": "**[P1 (High)] ...**\n\n...\n\n<!-- pr-review -->"
    }
  ]
}
EOF
gh api repos/OWNER/REPO/pulls/NUMBER/reviews -X POST --input review.json
```

- `line` は変更後のファイルの行番号で、差分に含まれる行である必要がある。複数行にまたがる場合は `start_line` と `start_side` も指定する。
- `suggestion` ブロックはコメント本文に次のように書く（指定した行が置き換え対象になる）:
  ````
  ```suggestion
  修正後のコード
  ```
  ````
- 差分外の行には付けられないため、その場合は関係の深い変更行に付ける。

ファイル単位のコメント（行に紐づかない指摘）は、レビューとは別に投稿する:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments -X POST \
  -f commit_id=HEAD_SHA -f path=src/foo.py -f subject_type=file \
  -f body='**[P2 (Medium)] ...**

<!-- pr-review -->'
```

### Approve（作者と別アカウントの場合のみ）

マージ判定の条件を満たしたときに投稿する。作者と同じアカウントでは失敗する。

```bash
gh pr review PR_URL --approve --body 'マージ条件をすべて満たしたことを確認しました（HEAD_SHA）。

<!-- pr-review -->'
```

作者のログイン名は `gh pr view PR_URL --json author --jq .author.login`、自分のログイン名は `gh api user --jq .login` で確認できる。

GraphQL が使えない環境では:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/reviews -X POST -f event=APPROVE \
  -f body='マージ条件をすべて満たしたことを確認しました（HEAD_SHA）。

<!-- pr-review -->'
gh api repos/OWNER/REPO/pulls/NUMBER --jq .user.login   # 作者のログイン名
```

## 3. スレッドの取得・返信・resolve

スレッドの一覧（resolve済みかどうか、各コメント）:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first:50) {
            nodes { databaseId body author { login } createdAt url }
          }
        }
      }
    }
  }
}' -F owner=OWNER -F repo=REPO -F number=NUMBER
```

- このスキルのスレッドは、最初のコメントの本文に `<!-- pr-review -->` を含むもの。
- 返信の有無は、最後のコメントがマーカーなしかどうかで判断する。

スレッドへの返信:

```bash
gh api graphql -f query='
mutation($id:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id, body:$body}) { comment { url } }
}' -F id=THREAD_ID -f body='確認しました（abc1234 で修正済み）。

<!-- pr-review -->'
```

resolve:

```bash
gh api graphql -f query='
mutation($id:ID!) { resolveReviewThread(input:{threadId:$id}) { thread { isResolved } } }' -F id=THREAD_ID
```

PR全体へのコメント（マージ前の記録など）:

```bash
gh pr comment PR_URL --body '...

<!-- pr-review -->'
```

### GraphQL が使えない環境では

スレッドの一覧は CCR ルートで取得する。返るのはスレッドごとの状態とコメントの ID だけなので、本文や作成者はレビューコメントの一覧から ID で引く:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/ccr/review_threads
# [{"resolved":false,"outdated":false,"path":"src/foo.py","line":42,"comment_ids":[123,456]}, ...]
gh api --paginate "repos/OWNER/REPO/pulls/NUMBER/comments?per_page=100" \
  --jq '.[] | {id, user: .user.login, body, created_at, in_reply_to_id, html_url}'
```

- `comment_ids` は投稿順で、先頭がスレッドの最初のコメント（以下、ルートコメント）。スレッドの ID（`THREAD_ID`）は取得できないので、返信と resolve にはルートコメントの ID を使う。
- このスキルのスレッドかどうか、返信があるかどうかは、GraphQL の場合と同じくマーカーの有無で判断する。

スレッドへの返信（REST。GraphQL が使える環境でも使える）:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments/ROOT_COMMENT_ID/replies -X POST \
  -f body='確認しました（abc1234 で修正済み）。

<!-- pr-review -->'
```

resolve（resolve を取り消すときは `resolve` を `unresolve` にする）:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/ccr/comments/ROOT_COMMENT_ID/resolve -X POST
# {"comment_ids":[123,456],"resolved":true}
```

PR全体へのコメント:

```bash
gh api repos/OWNER/REPO/issues/NUMBER/comments -X POST -f body='...

<!-- pr-review -->'
```

## 4. issueの確認

```bash
gh issue view ISSUE_NUMBER --repo OWNER/REPO --json number,title,body,state,url
# GraphQL が使えない環境では
gh api repos/OWNER/REPO/issues/ISSUE_NUMBER --jq '{number, title, body, state, url: .html_url}'
gh api --paginate "repos/OWNER/REPO/issues/ISSUE_NUMBER/comments?per_page=100" --jq '.[] | {user: .user.login, body, created_at}'
```

### issueに対応するPRを探す

issueを閉じる予定のPR（`Closes #123` などのキーワードや、PRの画面でissueをリンクしたもの）と、issueを参照しているPRの両方を取得する:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    issue(number:$number) {
      state
      closedByPullRequestsReferences(first:10, includeClosedPrs:true) {
        nodes { number url state isDraft headRefName createdAt }
      }
      timelineItems(itemTypes:[CROSS_REFERENCED_EVENT], last:20) {
        nodes {
          ... on CrossReferencedEvent {
            source { ... on PullRequest { number url state isDraft headRefName createdAt } }
          }
        }
      }
    }
  }
}' -F owner=OWNER -F repo=REPO -F number=ISSUE_NUMBER
```

- `closedByPullRequestsReferences` にあるPRを優先する。こちらはissueの解決を目的としたPR。
- `timelineItems` のPRは、issueに言及しているだけのこともあるので、PRの本文やタイトルを見て対応するものか確認する。
- どちらにもない場合の補助として、本文でissueに言及しているPRを検索する:
  ```bash
  gh pr list --repo OWNER/REPO --state open --search "ISSUE_NUMBER in:body" --json number,title,url,isDraft
  ```

#### GraphQL が使えない環境では

`closedByPullRequestsReferences` に相当する REST のエンドポイントはない。issueのタイムラインで、issueに言及したPR（`cross-referenced` イベント）を取得する:

```bash
gh api --paginate "repos/OWNER/REPO/issues/ISSUE_NUMBER/timeline?per_page=100" --jq '
  .[] | select(.event == "cross-referenced" and .source.issue.pull_request != null
               and .source.issue.repository.full_name == "OWNER/REPO")
  | .source.issue | {number, url: .html_url, state, draft, merged_at: .pull_request.merged_at, body}'
```

- PRの本文に `Closes #ISSUE_NUMBER` などのキーワード（close・fix・resolve とその活用形）があるものを、issueを閉じる予定のPRとして優先する。PRの画面で手動でリンクしただけのPRは、この方法では見分けられない。
- それ以外のPRは、issueに言及しているだけのこともあるので、PRの本文やタイトルを見て対応するものか確認する。
- `search/issues` は使えないことがあるので、どちらにもない場合の補助は、オープンなPRの本文を直接調べる:
  ```bash
  gh api --paginate "repos/OWNER/REPO/pulls?state=open&per_page=100" \
    --jq '.[] | select(.body // "" | test("#ISSUE_NUMBER\\b")) | {number, title, url: .html_url, draft}'
  ```

## 5. マージ方式の判定

許可されている方式と、ブランチの自動削除の設定:

```bash
gh api repos/OWNER/REPO --jq '{allow_merge_commit, allow_squash_merge, allow_rebase_merge, delete_branch_on_merge}'
```

既存のマージ済みPRの方式を推定する（直近10件程度）:

```bash
gh pr list --repo OWNER/REPO --state merged --limit 10 --json number,mergeCommit,commits \
  --jq '.[] | {number, sha: .mergeCommit.oid, commits: (.commits | length)}'
gh api repos/OWNER/REPO/commits/SHA --jq '{parents: (.parents | length), message: .commit.message}'
```

- 親が2つ → merge
- 親が1つで、メッセージがPRのタイトルと `(#番号)` で始まる → squash
- 親が1つで、それ以外（PRの各コミットがそのまま並んでいる） → rebase

多数派の方式を採用する。許可されていない方式は選ばない。

GraphQL が使えない環境では、`gh pr list` の代わりに次を使う（`merged_at` があるものがマージ済み）:

```bash
gh api "repos/OWNER/REPO/pulls?state=closed&per_page=30" \
  --jq '.[] | select(.merged_at != null) | {number, title, sha: .merge_commit_sha}' | head -10
gh api repos/OWNER/REPO/pulls/NUMBER --jq .commits   # PRのコミット数
```

## 6. マージ

```bash
gh pr merge PR_URL --squash --delete-branch --match-head-commit HEAD_SHA
# --merge / --squash / --rebase のいずれか
```

- `--match-head-commit` を付けると、確認したSHAから変わっていた場合にマージが失敗する。確認していないコミットのマージを防げる。
- squashやmergeのときは、`--subject` と `--body` を指定しない（リポジトリの既定のメッセージ、通常はPRのタイトルと本文が使われる）。
- リポジトリで自動削除が有効なら `--delete-branch` は不要だが、付けても害はない。

GraphQL が使えない環境では:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/merge -X PUT -f merge_method=squash -f sha=HEAD_SHA
# merge_method は merge / squash / rebase のいずれか
# 自動削除が無効なら、マージ後にブランチを削除する
gh api repos/OWNER/REPO/git/refs/heads/HEAD_BRANCH -X DELETE
```

- `sha` を付けると、確認したSHAから変わっていた場合にマージが失敗する（`--match-head-commit` と同じ）。
- `commit_title` と `commit_message` は指定しない（リポジトリの既定のメッセージに任せる）。
