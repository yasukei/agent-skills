#!/usr/bin/env bash
# PRの状態（CI・レビュー・レビュースレッド・PRコメント）をまとめてJSONで出力する。
# 使い方: pr_status.sh <PR番号> [owner/repo]
#   owner/repo を省略するとカレントディレクトリのリポジトリを使う。
# 必要: gh（認証済み）, jq
#
# 通常は GraphQL と gh pr checks で取得する。GraphQL が 403 で拒否される環境
# （クラウド版 Claude Code など）では、REST API とレビュースレッド用の CCR ルート
# （GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads）に切り替える。
# gh pr checks に --json がない古い gh（2.46 など）では、CI だけ REST で取得する。
# どちらの経路でも出力の JSON の形は同じ。ただし REST の経路では、
# reviewDecision は常に null、threads[].id（GraphQL のスレッド ID）は null になる。
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <PR番号> [owner/repo]" >&2
  exit 1
fi

PR="$1"
# gh repo view は GraphQL を使うので、REST で現在のリポジトリを解決する
# shellcheck disable=SC2016
REPO="${2:-$(gh api 'repos/{owner}/{repo}' --jq .full_name)}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

TMP="$(mktemp -d)"
API=graphql
# REST の経路で失敗したときは、切り替えのきっかけになった GraphQL のエラーも出す。
# 403 の原因が GraphQL の拒否ではなかった場合（SAML SSO など）に、原因を追えるようにするため
on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$API" = rest ]; then
    echo "REST での取得に失敗しました。REST に切り替える前の GraphQL のエラー:" >&2
    cat "$TMP/graphql.err" >&2
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT

# $owner などは GraphQL の変数で、シェルで展開するものではない
# shellcheck disable=SC2016
QUERY='
query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      url
      state
      isDraft
      mergeable
      reviewDecision
      author { login }
      headRefName
      headRefOid
      baseRefName
      reviews(last: 50) {
        nodes { author { login __typename } state submittedAt body }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes { databaseId author { login __typename } body createdAt url }
          }
        }
      }
      comments(last: 50) {
        nodes { databaseId author { login __typename } body createdAt url }
      }
    }
  }
}'

# REST の応答を GraphQL の pullRequest と同じ形に変換して出力する。
# 引数: PR・レビュー・レビューコメント・PRコメント・CCR ルートのスレッドの JSON が入ったファイル
rest_pr_json() {
  jq -n --slurpfile pr "$1" --slurpfile reviews "$2" --slurpfile comments "$3" \
    --slurpfile issueComments "$4" --slurpfile threads "$5" '
    $pr[0] as $pr
    | def author: { login: (.user.login // "ghost"), __typename: (if .user.type == "Bot" then "Bot" else "User" end) };
      def node: { databaseId: .id, author: author, body: (.body // ""), createdAt: .created_at, url: .html_url };
    ($comments[0] | map({ key: (.id | tostring), value: node }) | from_entries) as $byId
    | {
        url: $pr.html_url,
        state: (if $pr.merged then "MERGED" elif $pr.state == "closed" then "CLOSED" else "OPEN" end),
        isDraft: $pr.draft,
        mergeable: (if $pr.mergeable == true then "MERGEABLE"
                    elif $pr.mergeable == false then "CONFLICTING"
                    else "UNKNOWN" end),
        reviewDecision: null,
        author: { login: $pr.user.login },
        headRefName: $pr.head.ref,
        baseRefName: $pr.base.ref,
        reviews: { nodes: [ $reviews[0][] | { author: author, state, submittedAt: .submitted_at, body: (.body // "") } ] },
        # CCR ルートはスレッドごとにコメントの ID だけを返すので、レビューコメントの一覧から本文などを引く。
        # 一覧にないコメント（未送信のレビューのものなど）は除き、コメントが残らないスレッドも除く
        reviewThreads: { nodes: [ $threads[0][] | {
          id: null, isResolved: .resolved, isOutdated: .outdated, path, line,
          comments: { nodes: [ .comment_ids[] | tostring | $byId[.] | select(. != null) ] }
        } | select(.comments.nodes | length > 0) ] },
        comments: { nodes: [ $issueComments[0][] | node ] }
      }'
}

# REST のチェック（check runs とコミットステータス）を gh pr checks --json name,state,bucket,link,workflow と
# 同じ形に変換して出力する。bucket の分け方と重複の除き方は gh pr checks に合わせる。
# 引数: check runs・コミットステータス・ワークフローの実行の JSON が入ったファイル
rest_checks_json() {
  jq -n --slurpfile runs "$1" --slurpfile statuses "$2" --slurpfile workflowRuns "$3" '
    def bucket:
      if . == "SUCCESS" then "pass"
      elif IN("SKIPPED", "NEUTRAL") then "skipping"
      elif IN("FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE") then "fail"
      elif . == "CANCELLED" then "cancel"
      else "pending" end;
    ($workflowRuns[0] | map({ key: (.check_suite_id | tostring), value: { name, event } }) | from_entries) as $workflow
    # 同じコミットでワークフローが再実行されると、check-runs は古い check suite の同名のチェックも返す。
    # gh pr checks と同じく、チェック名・ワークフロー名・イベントごとに開始が最も新しいものだけを残す。
    # ワークフローの実行が分からない check suite（取得の失敗、Actions 以外のアプリなど）は、別のワークフローの
    # 失敗を消さないよう、check suite ごとに別のチェックとして扱う
    | [ $runs[0] | to_entries[]
        | .key as $i | .value
        | (.check_suite.id | tostring) as $suite
        | ($workflow[$suite] // { name: "", event: "" }) as $wf
        | ((if .status == "completed" then .conclusion else .status end) // "" | ascii_upcase) as $state
        | { i: $i,
            key: (if $workflow[$suite] then [.name, $wf.name, $wf.event] else [.name, "", "", $suite] end),
            startedAt: (.started_at // ""),
            check: { name, state: $state, bucket: ($state | bucket), link: (.details_url // .html_url // ""),
                     workflow: $wf.name } } ]
    | group_by(.key) | map(max_by([.startedAt, -.i])) | sort_by(.i) | map(.check)
    # コミットステータスは、コンテキストごとの最新だけが返る
    + [ $statuses[0][]
        | (.state | ascii_upcase) as $state
        | { name: .context, state: $state, bucket: ($state | bucket), link: (.target_url // ""), workflow: "" } ]'
}

# gh api --paginate は、ページごとの JSON を連結して出力する。各ページの <フィールド>（省略時はページ全体）の
# 配列をつなげて、1つの配列にする
paginate() {
  local field="$1"
  shift
  gh api --paginate "$@" | jq -s --arg f "$field" 'map(if $f == "" then . else .[$f] end) | add // []'
}

# REST でコミットのチェックを取得し、gh pr checks --json と同じ形で $TMP/checks.json に書く。
# 取得の失敗で止まるよう、コマンド置換の中ではなく、そのまま呼び出す
# 引数: repos/<owner>/<repo>、コミットの SHA
rest_checks() {
  local base="$1" sha="$2"
  paginate check_runs "$base/commits/$sha/check-runs?per_page=100" >"$TMP/check-runs.json"
  paginate statuses "$base/commits/$sha/status?per_page=100" >"$TMP/statuses.json"
  # ワークフロー名とイベントは check run に含まれないので、ワークフローの実行から引く。取れなければ空文字にする
  paginate workflow_runs "$base/actions/runs?head_sha=$sha&per_page=100" >"$TMP/workflow-runs.json" 2>/dev/null \
    || echo '[]' >"$TMP/workflow-runs.json"
  rest_checks_json "$TMP/check-runs.json" "$TMP/statuses.json" "$TMP/workflow-runs.json" >"$TMP/checks.json"
}

# まず GraphQL で取得し、403 で拒否されたら REST に切り替える
if gh api graphql -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" -F pr="$PR" \
  >"$TMP/graphql.json" 2>"$TMP/graphql.err"; then
  PR_JSON="$(jq '.data.repository.pullRequest' "$TMP/graphql.json")"

  # CI。gh pr checks は失敗時に1、pending時に8で終わるが、どちらもJSONは出力するので
  # 終了コードではなく出力で判断する。チェックがひとつもない場合だけ空配列として扱う
  CHECKS_RC=0
  CHECKS_JSON="$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link,workflow 2>"$TMP/checks.err")" || CHECKS_RC=$?
  if [ -n "$CHECKS_JSON" ] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$CHECKS_JSON"; then
    :
  elif grep -q "no checks reported" "$TMP/checks.err"; then
    CHECKS_JSON='[]'
  elif grep -q "unknown flag: --json" "$TMP/checks.err"; then
    # gh pr checks に --json がない古い gh では、REST で取得する
    rest_checks "repos/$OWNER/$NAME" "$(jq -r '.headRefOid' <<<"$PR_JSON")"
    CHECKS_JSON="$(cat "$TMP/checks.json")"
  else
    echo "gh pr checks に失敗しました（終了コード $CHECKS_RC）:" >&2
    cat "$TMP/checks.err" >&2
    exit 1
  fi
elif grep -Eq 'HTTP 403|GraphQL is not available' "$TMP/graphql.err"; then
  API=rest
  BASE="repos/$OWNER/$NAME"
  gh api "$BASE/pulls/$PR" >"$TMP/pr.json"
  paginate "" "$BASE/pulls/$PR/reviews?per_page=100" >"$TMP/reviews.json"
  paginate "" "$BASE/pulls/$PR/comments?per_page=100" >"$TMP/comments.json"
  paginate "" "$BASE/issues/$PR/comments?per_page=100" >"$TMP/issue-comments.json"
  gh api "$BASE/pulls/$PR/ccr/review_threads" >"$TMP/threads.json"
  PR_JSON="$(rest_pr_json "$TMP/pr.json" "$TMP/reviews.json" "$TMP/comments.json" \
    "$TMP/issue-comments.json" "$TMP/threads.json")"

  rest_checks "$BASE" "$(jq -r '.head.sha' "$TMP/pr.json")"
  CHECKS_JSON="$(cat "$TMP/checks.json")"
else
  echo "GraphQL での PR の取得に失敗しました:" >&2
  cat "$TMP/graphql.err" >&2
  exit 1
fi

# このスキルが投稿したコメントに付けるマーカー。作者とレビュアーが同じアカウントでも区別できる
MARKER='<!-- issue-to-pr -->'
# レビュアーが「指摘なしでレビューを完了した」ことを明示するマーカー（同一アカウントでの完了の合図）
COMPLETE_MARKER='<!-- review-complete -->'

jq -n --argjson pr "$PR_JSON" --argjson checks "$CHECKS_JSON" \
  --arg marker "$MARKER" --arg complete "$COMPLETE_MARKER" '
  ($pr.author.login) as $author
  | (if ($checks | length) == 0 then "none"
     elif any($checks[]; .bucket == "fail" or .bucket == "cancel") then "failing"
     elif any($checks[]; .bucket == "pending") then "pending"
     else "passing" end) as $ci
  # レビュー側の活動（マーカーのないもの）。このスキル自身の返信やPR本文は含めない。
  # スレッドへの返信をすると、本文が空の COMMENTED レビューが作者名義で作られるため、それも除く。
  # bot（Copilot、カバレッジの報告など）はApproveも完了の合図もしないので、レビュアーとして数えない
  | def human: (.author.__typename // "User") != "Bot" and (.author.login // "" | endswith("[bot]") | not);
    def notMine: .body // "" | contains($marker) | not;
  [ $pr.reviews.nodes[]
      | select(human and notMine and ((.body // "") != "" or .state != "COMMENTED"))
      | . + { at: .submittedAt } ] as $reviewerReviews
  | [ $pr.reviewThreads.nodes[] | select(.comments.nodes[0] | human and notMine) ] as $reviewerThreads
  | [ $pr.reviewThreads.nodes[].comments.nodes[] | select(human and notMine) | . + { at: .createdAt } ] as $reviewerThreadComments
  | [ $pr.comments.nodes[] | select(human and notMine) | . + { at: .createdAt } ] as $reviewerIssueComments
  | ($reviewerReviews + $reviewerThreadComments + $reviewerIssueComments) as $reviewerActivity
  | (($reviewerActivity | length) > 0) as $activity
  | any($reviewerActivity[]; .author.login != $author) as $hasOther
  | ([ $pr.reviews.nodes[] | select(human and .author.login != $author and .state != "COMMENTED") ]
     | group_by(.author.login) | map(max_by(.submittedAt))) as $latestOthers
  | ([ $reviewerThreads[] | select(.isResolved | not) ] | length) as $unresolvedReviewer
  # 完了マーカーは、それより後にレビュー側の活動（質問など）がない場合だけ有効にする
  | ([ ($reviewerReviews + $reviewerIssueComments)[] | select(.body // "" | contains($complete)) | .at ] | max) as $completedAt
  | ($completedAt != null and all($reviewerActivity[]; .at <= $completedAt)) as $explicit
  | (if $pr.state == "MERGED" then ["merged", "PRがマージされた"]
     elif $pr.state == "CLOSED" then ["closed", "PRがクローズされた"]
     elif $ci == "failing" then ["ci_failing", "CIが失敗している"]
     elif $ci == "pending" then ["ci_pending", "CIが実行中"]
     elif $pr.mergeable == "CONFLICTING" then ["conflicting", "ベースブランチとコンフリクトしている"]
     elif $pr.mergeable != "MERGEABLE" then ["mergeable_unknown", "マージできるかをGitHubが計算中"]
     elif ($activity | not) then ["waiting_for_review", "レビュー側の活動がまだない"]
     elif $hasOther then
       (if ($latestOthers | length) > 0 and all($latestOthers[]; .state == "APPROVED")
        then ["ready", "作成者以外の最新レビューがApprove"]
        else ["review_in_progress", "作成者以外のアカウントのApprove待ち"] end)
     elif $unresolvedReviewer > 0 then ["review_in_progress", "未解決のレビュースレッドがある"]
     elif ($reviewerThreads | length) > 0 then ["ready", "レビュースレッドがすべてresolve済み"]
     elif $explicit then ["ready", "レビュー完了・指摘なしの合図がある"]
     else ["review_in_progress", "レビュー完了の合図（スレッドのresolveまたは完了マーカー）がまだない"] end
    ) as $v
  | {
      url: $pr.url,
      state: $pr.state,
      mergeable: $pr.mergeable,
      reviewDecision: $pr.reviewDecision,
      author: $author,
      head: $pr.headRefName,
      base: $pr.baseRefName,
      # 終了条件の判定。done が true になるまで監視を続ける（SKILL.md の「終了条件」）
      verdict: { status: $v[0], done: ($v[0] | IN("ready", "merged", "closed")), reason: $v[1] },
      ci: {
        summary: $ci,
        failing: [ $checks[] | select(.bucket == "fail" or .bucket == "cancel") ],
        pending: [ $checks[] | select(.bucket == "pending") | .name ]
      },
      review: {
        # マーカーのないレビュー・スレッドのコメント・PRコメントがあるか。false なら「レビュー待ち」
        activity: $activity,
        # 作成者以外のアカウントがレビューしているか（終了条件の判定に使う）
        mode: (if $hasOther then "other_account" elif $activity then "same_account" else "none" end),
        explicitCompletion: $explicit,
        reviewerThreadCount: ($reviewerThreads | length),
        unresolvedReviewerThreadCount: $unresolvedReviewer
      },
      hasOtherReviewer: $hasOther,
      latestReviewByOthers: $latestOthers,
      reviews: $pr.reviews.nodes,
      unresolvedThreadCount: ([ $pr.reviewThreads.nodes[] | select(.isResolved | not) ] | length),
      threads: [
        $pr.reviewThreads.nodes[] | {
          id, isResolved, isOutdated, path, line,
          rootCommentId: .comments.nodes[0].databaseId,
          comments: .comments.nodes,
          # 最後のコメントにマーカーがなければ、レビュアーのコメントに未返信の可能性がある
          lastCommentByMe: (.comments.nodes[-1].body | contains($marker))
        }
      ],
      issueComments: [ $pr.comments.nodes[] | . + { byMe: (.body | contains($marker)) } ]
    }
'
