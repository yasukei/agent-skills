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
        nodes { author { login } state submittedAt body }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes { databaseId author { login } body createdAt url }
          }
        }
      }
      comments(last: 50) {
        nodes { databaseId author { login } body createdAt url }
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

jq -n --argjson pr "$PR_JSON" --argjson checks "$CHECKS_JSON" '
  ($pr.author.login) as $author
  | {
      url: $pr.url,
      state: $pr.state,
      mergeable: $pr.mergeable,
      reviewDecision: $pr.reviewDecision,
      author: $author,
      head: $pr.headRefName,
      base: $pr.baseRefName,
      ci: {
        summary: (
          if ($checks | length) == 0 then "none"
          elif any($checks[]; .bucket == "fail" or .bucket == "cancel") then "failing"
          elif any($checks[]; .bucket == "pending") then "pending"
          else "passing" end
        ),
        failing: [ $checks[] | select(.bucket == "fail" or .bucket == "cancel") ],
        pending: [ $checks[] | select(.bucket == "pending") | .name ]
      },
      # 作成者以外のアカウントがレビューしているか（終了条件の判定に使う）
      hasOtherReviewer: (
        any($pr.reviews.nodes[]; .author.login != $author)
        or any($pr.reviewThreads.nodes[].comments.nodes[]; .author.login != $author)
      ),
      latestReviewByOthers: (
        [ $pr.reviews.nodes[] | select(.author.login != $author and .state != "COMMENTED") ]
        | group_by(.author.login) | map(max_by(.submittedAt))
      ),
      reviews: $pr.reviews.nodes,
      unresolvedThreadCount: ([ $pr.reviewThreads.nodes[] | select(.isResolved | not) ] | length),
      threads: [
        $pr.reviewThreads.nodes[] | {
          id, isResolved, isOutdated, path, line,
          rootCommentId: .comments.nodes[0].databaseId,
          comments: .comments.nodes,
          # 最後の発言者がこちら（作成者）以外なら、未返信の可能性がある
          lastCommentByAuthor: (.comments.nodes[-1].author.login == $author)
        }
      ],
      issueComments: $pr.comments.nodes
    }
'
