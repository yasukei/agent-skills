# GitHub操作のコマンド集

`gh` CLI を使う。`OWNER`、`REPO`、`NUMBER`、`PR_URL` は対象のPRに置き換える。

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

言語の判定用に、最近のPRとレビューコメントを見る:

```bash
gh pr list --repo OWNER/REPO --state all --limit 5 --json number,title,body
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

## 4. issueの確認

```bash
gh issue view ISSUE_NUMBER --repo OWNER/REPO --json number,title,body,state,url
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

## 6. マージ

```bash
gh pr merge PR_URL --squash --delete-branch --match-head-commit HEAD_SHA
# --merge / --squash / --rebase のいずれか
```

- `--match-head-commit` を付けると、確認したSHAから変わっていた場合にマージが失敗する。確認していないコミットのマージを防げる。
- squashやmergeのときは、`--subject` と `--body` を指定しない（リポジトリの既定のメッセージ、通常はPRのタイトルと本文が使われる）。
- リポジトリで自動削除が有効なら `--delete-branch` は不要だが、付けても害はない。
