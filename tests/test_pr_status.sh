#!/usr/bin/env bash
# skills/issue-to-pr/scripts/pr_status.sh のテスト。
# PATH の先頭に偽の gh（tests/fake-bin/gh）を置き、GitHub の認証やネットワークに依存せずに実行する。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/issue-to-pr/scripts/pr_status.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/tests/fake-bin:$PATH"
export FAKE_GRAPHQL="$WORK/graphql.json"
export FAKE_GH_LOG="$WORK/gh.log"

# gh api graphql の出力を作る。
#   write_pr <state> <mergeable> <reviews> <reviewThreads> <comments>
# 後ろ3つは nodes の JSON 配列。PR の作成者は "me"
write_pr() {
  jq -n --arg state "$1" --arg mergeable "$2" \
    --argjson reviews "$3" --argjson threads "$4" --argjson comments "$5" '{
    data: { repository: { pullRequest: {
      url: "https://github.com/o/r/pull/1",
      state: $state, isDraft: false, mergeable: $mergeable, reviewDecision: null,
      author: { login: "me" }, headRefName: "feat/1-x", baseRefName: "main",
      reviews: { nodes: $reviews },
      reviewThreads: { nodes: $threads },
      comments: { nodes: $comments }
    } } }
  }' >"$FAKE_GRAPHQL"
}

# レビュースレッドを1つ作る: <isResolved> <作成者> <最初のコメント本文> [<作成者> <本文>]...
thread() {
  local resolved="$1"
  shift
  local comments='[]' i=1
  while [ $# -ge 2 ]; do
    comments="$(jq -c --arg a "$1" --arg b "$2" --argjson i "$i" \
      '. + [{ databaseId: $i, author: { login: $a }, body: $b, createdAt: "2026-01-01T00:00:00Z", url: "u\($i)" }]' \
      <<<"$comments")"
    i=$((i + 1))
    shift 2
  done
  jq -nc --argjson r "$resolved" --argjson c "$comments" \
    '{ id: "T1", isResolved: $r, isOutdated: false, path: "a.sh", line: 1, comments: { nodes: $c } }'
}

# レビューを1つ作る: <作成者> <state> <本文>
review() {
  jq -nc --arg a "$1" --arg s "$2" --arg b "$3" \
    '{ author: { login: $a }, state: $s, submittedAt: "2026-01-01T00:00:00Z", body: $b }'
}

# PRコメントを1つ作る: <作成者> <本文>
comment() {
  jq -nc --arg a "$1" --arg b "$2" \
    '{ databaseId: 100, author: { login: $a }, body: $b, createdAt: "2026-01-01T00:00:00Z", url: "c" }'
}

# 従来のテスト用: 未解決スレッド1つ（最初のコメントはレビュアー、2件目の本文を引数で指定）
write_graphql() {
  write_pr OPEN MERGEABLE '[]' "[$(thread false me "[P2] 直してください" me "$1")]" '[]'
}

# pr_status.sh を実行し、OUT・ERR・RC に結果を入れる
run_status() {
  RC=0
  "$SCRIPT" 1 o/r >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# 偽の gh pr checks の結果を設定する: <標準出力> <標準エラー> <終了コード>
checks() {
  export FAKE_CHECKS_OUT="$1" FAKE_CHECKS_ERR="$2" FAKE_CHECKS_RC="$3"
}

field() {
  jq -r "$1" <<<"$OUT"
}

PASS_CHECK='{"name":"test","state":"SUCCESS","bucket":"pass","link":"l1","workflow":"CI"}'
FAIL_CHECK='{"name":"lint","state":"FAILURE","bucket":"fail","link":"l2","workflow":"CI"}'
PENDING_CHECK='{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"l3","workflow":"CI"}'

write_graphql "nullチェックを追加しました（abc1234）

<!-- issue-to-pr -->"

# ---------------------------------------------------------------------------
t "CI 成功"
checks "[$PASS_CHECK]" "" 0
run_status
assert_eq 0 "$RC" "終了コード"
assert_eq passing "$(field .ci.summary)" "ci.summary"
assert_eq 0 "$(field '.ci.failing | length')" "ci.failing"
assert_contains "$(cat "$FAKE_GH_LOG")" "pr checks 1 --repo o/r --json" "gh pr checks に PR 番号とリポジトリを渡す"
assert_contains "$(cat "$FAKE_GH_LOG")" "-F owner=o -F name=r -F pr=1" "GraphQL に owner・name・PR 番号を渡す"

# ---------------------------------------------------------------------------
t "CI 失敗"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
run_status
assert_eq 0 "$RC" "終了コード"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq lint "$(field '.ci.failing | map(.name) | join(",")')" "ci.failing"

# ---------------------------------------------------------------------------
t "CI pending"
checks "[$PASS_CHECK,$PENDING_CHECK]" "" 8
run_status
assert_eq 0 "$RC" "終了コード"
assert_eq pending "$(field .ci.summary)" "ci.summary"
assert_eq build "$(field '.ci.pending | join(",")')" "ci.pending"

# ---------------------------------------------------------------------------
t "チェックなし"
checks "" "no checks reported on the 'feat/1-x' branch" 1
run_status
assert_eq 0 "$RC" "終了コード"
assert_eq none "$(field .ci.summary)" "ci.summary"

# ---------------------------------------------------------------------------
t "それ以外の gh pr checks のエラー"
checks "" "HTTP 401: Bad credentials" 1
run_status
assert_eq 1 "$RC" "終了コード"
assert_eq "" "$OUT" "標準出力に結果を出さない"
assert_contains "$ERR" "HTTP 401: Bad credentials" "エラー内容を標準エラーに出す"

# ---------------------------------------------------------------------------
t "マーカー判定"
checks "[$PASS_CHECK]" "" 0
write_graphql "nullチェックを追加しました（abc1234）

<!-- issue-to-pr -->"
run_status
assert_eq true "$(field '.threads[0].lastCommentByMe')" "マーカーあり"
write_graphql "まだ直っていません"
run_status
assert_eq 0 "$RC" "終了コード"
assert_eq false "$(field '.threads[0].lastCommentByMe')" "マーカーなし"

# ---------------------------------------------------------------------------
# 終了条件の判定（verdict）

MINE='<!-- issue-to-pr -->'
BY_REVIEWER='<!-- pr-review -->'
COMPLETE='<!-- review-complete -->'

# assert_verdict <status> <done> <説明>
assert_verdict() {
  assert_eq 0 "$RC" "$3: 終了コード"
  assert_eq "$1" "$(field .verdict.status)" "$3: verdict.status"
  assert_eq "$2" "$(field .verdict.done)" "$3: verdict.done"
}

checks "[$PASS_CHECK]" "" 0

t "CI 成功・レビュー0件・スレッド0件はレビュー待ち"
write_pr OPEN MERGEABLE '[]' '[]' '[]'
run_status
assert_verdict waiting_for_review false "レビューなし"
assert_eq false "$(field .review.activity)" "review.activity"
assert_eq none "$(field .review.mode)" "review.mode"

t "自分のマーカー付き返信だけではレビュー済みにしない"
# スレッドに返信すると、本文が空の COMMENTED レビューが作者名義で作られる
write_pr OPEN MERGEABLE "[$(review me COMMENTED "")]" '[]' \
  "[$(comment me "PRを作成しました。

$MINE")]"
run_status
assert_verdict waiting_for_review false "自分の返信だけ"

t "完了マーカーが自分の投稿にあっても完了にしない"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment me "レビュー完了 $COMPLETE

$MINE")]"
run_status
assert_verdict waiting_for_review false "自分の投稿の完了マーカー"

t "同一アカウント: 途中の質問（未解決スレッド）は完了にしない"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "質問があります。

$BY_REVIEWER")]" \
  "[$(thread false me "[Question] これは意図通りですか？

$BY_REVIEWER")]" '[]'
run_status
assert_verdict review_in_progress false "未解決の質問スレッド"
assert_eq same_account "$(field .review.mode)" "review.mode"
assert_eq 1 "$(field .review.unresolvedReviewerThreadCount)" "未解決スレッド数"

t "同一アカウント: PRコメントでの途中の質問は完了にしない"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment me "この関数はどこから呼ばれますか？")]"
run_status
assert_verdict review_in_progress false "PRコメントの質問"
assert_eq false "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "同一アカウント: 明示的なレビュー完了・指摘なしで終了できる"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "指摘はありません。

$COMPLETE
$BY_REVIEWER")]" '[]' '[]'
run_status
assert_verdict ready true "完了マーカー付きレビュー"
assert_eq true "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "同一アカウント: 明示的な完了でもCI実行中なら終了しない"
checks "[$PASS_CHECK,$PENDING_CHECK]" "" 8
run_status
assert_verdict ci_pending false "CI実行中"
checks "[$PASS_CHECK]" "" 0

t "同一アカウント: 指摘スレッドがすべてresolve済みなら終了できる"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "## レビュー結果

$BY_REVIEWER")]" \
  "[$(thread true me "[P2] 直してください

$BY_REVIEWER" me "直しました（abc1234）

$MINE")]" '[]'
run_status
assert_verdict ready true "全スレッドresolve済み"

t "同一アカウント: 未解決の指摘スレッドがあれば終了しない"
write_pr OPEN MERGEABLE '[]' \
  "[$(thread false me "[P2] 直してください

$BY_REVIEWER" me "直しました（abc1234）

$MINE")]" '[]'
run_status
assert_verdict review_in_progress false "未解決スレッド"

t "同一アカウント: 未解決スレッドがあれば完了マーカーがあっても終了しない"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "$COMPLETE")]" \
  "[$(thread false me "[P1] 再指摘です")]" '[]'
run_status
assert_verdict review_in_progress false "完了マーカーと未解決スレッド"

t "別アカウント: Approve待ちでは終了しない"
write_pr OPEN MERGEABLE "[$(review alice COMMENTED "## レビュー結果")]" \
  "[$(thread true alice "[P3] 任意です")]" '[]'
run_status
assert_verdict review_in_progress false "COMMENTEDのみ"
assert_eq other_account "$(field .review.mode)" "review.mode"
write_pr OPEN MERGEABLE "[$(review alice CHANGES_REQUESTED "直してください")]" '[]' '[]'
run_status
assert_verdict review_in_progress false "変更要求"

t "別アカウント: 最新レビューがApproveなら終了できる"
write_pr OPEN MERGEABLE "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict ready true "Approve"

t "別アカウント: ApproveでもCI失敗中なら終了しない"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
run_status
assert_verdict ci_failing false "CI失敗"
checks "[$PASS_CHECK]" "" 0

t "コンフリクトしていれば終了しない"
write_pr OPEN CONFLICTING "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict conflicting false "コンフリクト"

t "マージ・クローズされたら終了する"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
write_pr MERGED UNKNOWN '[]' '[]' '[]'
run_status
assert_verdict merged true "マージ"
write_pr CLOSED UNKNOWN '[]' '[]' '[]'
run_status
assert_verdict closed true "クローズ"

done_testing
