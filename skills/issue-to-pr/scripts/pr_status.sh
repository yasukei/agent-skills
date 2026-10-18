#!/usr/bin/env bash
# PRの状態（CI・レビュー・レビュースレッド・PRコメント）をまとめてJSONで出力する。
# 使い方: pr_status.sh <PR番号> [owner/repo]
#   owner/repo を省略するとカレントディレクトリのリポジトリを使う。
# 必要: gh（認証済み）, jq
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <PR番号> [owner/repo]" >&2
  exit 1
fi

PR="$1"
REPO="${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

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

PR_JSON="$(gh api graphql -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" -F pr="$PR" \
  | jq '.data.repository.pullRequest')"

# CI。gh pr checks は失敗時に1、pending時に8で終わるが、どちらもJSONは出力するので
# 終了コードではなく出力で判断する。チェックがひとつもない場合だけ空配列として扱う
CHECKS_ERR="$(mktemp)"
trap 'rm -f "$CHECKS_ERR"' EXIT
CHECKS_RC=0
CHECKS_JSON="$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link,workflow 2>"$CHECKS_ERR")" || CHECKS_RC=$?
if [ -n "$CHECKS_JSON" ] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$CHECKS_JSON"; then
  :
elif grep -q "no checks reported" "$CHECKS_ERR"; then
  CHECKS_JSON='[]'
else
  echo "gh pr checks に失敗しました（終了コード $CHECKS_RC）:" >&2
  cat "$CHECKS_ERR" >&2
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
