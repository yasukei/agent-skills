#!/usr/bin/env bash
# skills/issue-to-pr/scripts/pr_status.sh のテスト。
# PATH の先頭に偽の gh（tests/fake-bin/gh）を置き、GitHub の認証やネットワークに依存せずに実行する。
# 各ケースは GraphQL の経路と、GraphQL が 403 になる環境での REST・CCR ルートの経路の両方で実行し、
# 同じ結果になることを確かめる（run_status）。
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
export FAKE_REST_DIR="$WORK/rest"
mkdir -p "$FAKE_REST_DIR"

# GraphQL が使えない環境（クラウド版 Claude Code）での gh api graphql のエラー
GRAPHQL_403='gh: GitHub GraphQL is not available from Claude Code sessions; use the REST API (gh api repos/{owner}/{repo}/...). (HTTP 403)'
# REST の経路で使う PR の head SHA
SHA=abc123

# 偽の gh api <パス> が返すファイルのパス
rest_file() {
  printf '%s/%s.json' "$FAKE_REST_DIR" "$(printf '%s' "$1" | tr / _)"
}

# GraphQL の応答（$FAKE_GRAPHQL）から、同じ内容の REST・CCR ルートの応答を作る
write_rest_from_graphql() {
  local pr
  pr="$(jq '.data.repository.pullRequest' "$FAKE_GRAPHQL")"
  jq --arg sha "$SHA" '{
    html_url: .url,
    state: (if .state == "OPEN" then "open" else "closed" end),
    merged: (.state == "MERGED"),
    draft: .isDraft,
    mergeable: (if .mergeable == "MERGEABLE" then true elif .mergeable == "CONFLICTING" then false else null end),
    user: { login: .author.login, type: "User" },
    head: { ref: .headRefName, sha: $sha },
    base: { ref: .baseRefName }
  }' <<<"$pr" >"$(rest_file repos/o/r/pulls/1)"
  local user='{ login: .author.login, type: (if .author.__typename == "Bot" then "Bot" else "User" end) }'
  jq "[ .reviews.nodes[] | { user: $user, state, submitted_at: .submittedAt, body } ]" <<<"$pr" \
    >"$(rest_file repos/o/r/pulls/1/reviews)"
  jq "[ .reviewThreads.nodes[].comments.nodes[] | { id: .databaseId, user: $user, body, created_at: .createdAt, html_url: .url } ]" \
    <<<"$pr" >"$(rest_file repos/o/r/pulls/1/comments)"
  jq "[ .comments.nodes[] | { id: .databaseId, user: $user, body, created_at: .createdAt, html_url: .url } ]" <<<"$pr" \
    >"$(rest_file repos/o/r/issues/1/comments)"
  jq '[ .reviewThreads.nodes[] | { resolved: .isResolved, outdated: .isOutdated, path, line,
        comment_ids: [ .comments.nodes[].databaseId ] } ]' <<<"$pr" \
    >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
}

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
  write_rest_from_graphql
}

# レビュースレッドを1つ作る: <isResolved> <作成者> <最初のコメント本文> [<作成者> <本文>]...
thread() {
  local resolved="$1"
  shift
  local comments='[]' i=1
  while [ $# -ge 2 ]; do
    comments="$(jq -c --arg a "$1" --arg b "$2" --argjson i "$i" \
      '. + [{ databaseId: $i, author: { login: $a, __typename: "User" }, body: $b, createdAt: "2026-01-01T00:00:00Z", url: "u\($i)" }]' \
      <<<"$comments")"
    i=$((i + 1))
    shift 2
  done
  jq -nc --argjson r "$resolved" --argjson c "$comments" \
    '{ id: "T1", isResolved: $r, isOutdated: false, path: "a.sh", line: 1, comments: { nodes: $c } }'
}

# レビューを1つ作る: <作成者> <state> <本文> [<日時>]
review() {
  jq -nc --arg a "$1" --arg s "$2" --arg b "$3" --arg at "${4:-2026-01-01T00:00:00Z}" \
    '{ author: { login: $a, __typename: "User" }, state: $s, submittedAt: $at, body: $b }'
}

# PRコメントを1つ作る: <作成者> <本文> [<日時>]
comment() {
  jq -nc --arg a "$1" --arg b "$2" --arg at "${3:-2026-01-01T00:00:00Z}" \
    '{ databaseId: 100, author: { login: $a, __typename: "User" }, body: $b, createdAt: $at, url: "c" }'
}

# 標準入力のレビューやコメントを bot の投稿にする
as_bot() {
  jq -c '.author.__typename = "Bot"'
}

# 従来のテスト用: 未解決スレッド1つ（最初のコメントはレビュアー、2件目の本文を引数で指定）
write_graphql() {
  write_pr OPEN MERGEABLE '[]' "[$(thread false me "[P2] 直してください" me "$1")]" '[]'
}

# pr_status.sh を1回実行し、OUT・ERR・RC に結果を入れる
run_once() {
  RC=0
  "$SCRIPT" 1 o/r >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# GraphQL が 403 になる環境（REST・CCR ルートの経路）で pr_status.sh を実行する
run_rest() {
  FAKE_GRAPHQL_RC=1 FAKE_GRAPHQL_ERR="$GRAPHQL_403" run_once
}

# pr_status.sh を GraphQL の経路と REST の経路の両方で実行し、結果が同じことを確かめる。
# OUT・ERR・RC には GraphQL の経路の結果を入れる。
# スレッドの ID は REST の経路では取得できない（null になる）ので比べない
run_status() {
  local rc out err
  run_rest
  rc="$RC" out="$OUT"
  run_once
  err="$ERR"
  assert_eq "$RC" "$rc" "REST の経路でも終了コードが同じ"
  if [ -z "$OUT" ] || [ -z "$out" ]; then
    assert_eq "$OUT" "$out" "REST の経路でも標準出力が同じ"
  elif jq -e -n --argjson g "$OUT" --argjson r "$out" \
    '($g | del(.threads[].id)) == ($r | del(.threads[].id))' >/dev/null; then
    pass
  else
    fail "REST の経路の出力が GraphQL の経路と異なる: $(diff <(jq -S 'del(.threads[].id)' <<<"$OUT") <(jq -S 'del(.threads[].id)' <<<"$out"))"
  fi
  ERR="$err"
}

# 偽の gh pr checks の結果を設定する: <標準出力> <標準エラー> <終了コード>
# REST の経路用に、同じ内容の check runs も作る。gh pr checks がエラーになる場合は、check runs も取得できなくする
checks() {
  export FAKE_CHECKS_OUT="$1" FAKE_CHECKS_ERR="$2" FAKE_CHECKS_RC="$3"
  local runs
  if [ -n "$1" ]; then
    runs="$(jq -c '[ .[] | {
      name,
      status: (if .bucket == "pending" then "in_progress" else "completed" end),
      conclusion: ({ pass: "success", fail: "failure", cancel: "cancelled", skipping: "skipped" }[.bucket]),
      details_url: .link,
      check_suite: { id: 1 }
    } ]' <<<"$1")"
  elif [[ "$2" == *"no checks reported"* ]]; then
    runs='[]'
  else
    rm -f "$(rest_file "repos/o/r/commits/$SHA/check-runs")"
    return
  fi
  jq -n --argjson r "$runs" '{ total_count: ($r | length), check_runs: $r }' \
    >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
  echo '{ "state": "pending", "statuses": [] }' >"$(rest_file "repos/o/r/commits/$SHA/status")"
  echo '{ "workflow_runs": [{ "check_suite_id": 1, "name": "CI" }] }' >"$(rest_file repos/o/r/actions/runs)"
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
assert_contains "$(cat "$FAKE_GH_LOG")" "repos/o/r/pulls/1/ccr/review_threads" "REST の経路ではスレッドを CCR ルートで取得する"
assert_contains "$(cat "$FAKE_GH_LOG")" "repos/o/r/commits/$SHA/check-runs" "REST の経路では head SHA の check runs を取得する"

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

t "同一アカウント: 完了マーカーの後に質問があれば完了にしない"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "指摘はありません。

$COMPLETE
$BY_REVIEWER" 2026-01-01T00:00:00Z)]" '[]' \
  "[$(comment me "もう一点、この変数名の意図は？" 2026-01-01T01:00:00Z)]"
run_status
assert_verdict review_in_progress false "完了マーカーの後の質問"
assert_eq false "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "bot の投稿だけではレビュー待ちのまま"
write_pr OPEN MERGEABLE "[$(review copilot-pull-request-reviewer COMMENTED "概要です" | as_bot)]" '[]' \
  "[$(comment codecov "Coverage: 90%" | as_bot)]"
run_status
assert_verdict waiting_for_review false "bot のみ"
assert_eq false "$(field .hasOtherReviewer)" "bot は別アカウントのレビュアーに数えない"

t "同一アカウント: bot のレビューがあっても完了マーカーで終了できる"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "指摘はありません。

$COMPLETE
$BY_REVIEWER"),$(review copilot-pull-request-reviewer COMMENTED "概要です" 2026-01-01T02:00:00Z | as_bot)]" '[]' '[]'
run_status
assert_verdict ready true "bot のレビューと完了マーカー"

t "別アカウント: PRコメントの完了マーカーだけでは終了しない"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment alice "LGTM $COMPLETE")]"
run_status
assert_verdict review_in_progress false "別アカウントの完了マーカー"
assert_eq other_account "$(field .review.mode)" "review.mode"

t "別アカウント: Approve済みなら未解決スレッドがあっても終了できる（Approveはレビュアーの判断）"
write_pr OPEN MERGEABLE "[$(review alice APPROVED "LGTM")]" "[$(thread false alice "[P3] 任意です")]" '[]'
run_status
assert_verdict ready true "Approveと未解決スレッド"

t "mergeable が未計算なら終了しない"
write_pr OPEN UNKNOWN "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict mergeable_unknown false "mergeable UNKNOWN"

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

# ---------------------------------------------------------------------------
# REST・CCR ルートの経路に固有のケース

checks "[$PASS_CHECK]" "" 0
write_pr OPEN MERGEABLE '[]' '[]' '[]'

t "REST: GraphQL が 403 のときは gh pr checks を呼ばない"
: >"$FAKE_GH_LOG"
run_rest
assert_verdict waiting_for_review false "REST の経路"
assert_contains "$(cat "$FAKE_GH_LOG")" "api graphql" "最初に GraphQL を試す"
if grep -q "^pr checks" "$FAKE_GH_LOG"; then fail "gh pr checks を呼んでいる"; else pass; fi

t "REST: GraphQL の 403 以外のエラーでは REST に切り替えない"
: >"$FAKE_GH_LOG"
FAKE_GRAPHQL_RC=1 FAKE_GRAPHQL_ERR="HTTP 502: Bad Gateway" run_once
assert_eq 1 "$RC" "終了コード"
assert_eq "" "$OUT" "標準出力に結果を出さない"
assert_contains "$ERR" "HTTP 502: Bad Gateway" "エラー内容を標準エラーに出す"
if grep -q "ccr/review_threads" "$FAKE_GH_LOG"; then fail "REST に切り替えている"; else pass; fi

t "REST: CCR ルートでスレッドを取得できなければエラーにする"
rm "$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_eq 1 "$RC" "終了コード"
assert_eq "" "$OUT" "標準出力に結果を出さない"
assert_contains "$ERR" "HTTP 404" "エラー内容を標準エラーに出す"
assert_contains "$ERR" "GraphQL is not available" "切り替える前の GraphQL のエラーも出す"
write_pr OPEN MERGEABLE '[]' '[]' '[]'

t "REST: check runs とコミットステータスの state と bucket"
jq -n '{ check_runs: [
  { name: "ok",       status: "completed",   conclusion: "success",         details_url: "d1", check_suite: { id: 1 } },
  { name: "skip",     status: "completed",   conclusion: "skipped",         details_url: "d2", check_suite: { id: 1 } },
  { name: "neutral",  status: "completed",   conclusion: "neutral",         details_url: "d3", check_suite: { id: 2 } },
  { name: "timeout",  status: "completed",   conclusion: "timed_out",       details_url: "d4", check_suite: { id: 1 } },
  { name: "action",   status: "completed",   conclusion: "action_required", details_url: "d5", check_suite: { id: 1 } },
  { name: "cancel",   status: "completed",   conclusion: "cancelled",       details_url: "d6", check_suite: { id: 1 } },
  { name: "queued",   status: "queued",      conclusion: null,              details_url: "d7", check_suite: { id: 1 } },
  { name: "running",  status: "in_progress", conclusion: null,              html_url: "h8",    check_suite: { id: 1 } }
] }' >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
jq -n '{ state: "failure", statuses: [
  { context: "ci/ext-ok",   state: "success", target_url: "s1" },
  { context: "ci/ext-err",  state: "error",   target_url: "s2" },
  { context: "ci/ext-fail", state: "failure", target_url: null },
  { context: "ci/ext-wait", state: "pending", target_url: "s4" }
] }' >"$(rest_file "repos/o/r/commits/$SHA/status")"
run_rest
assert_eq 0 "$RC" "終了コード"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq "timeout,action,cancel,ci/ext-err,ci/ext-fail" "$(field '.ci.failing | map(.name) | join(",")')" "ci.failing"
assert_eq "queued,running,ci/ext-wait" "$(field '.ci.pending | join(",")')" "ci.pending"
assert_eq "TIMED_OUT fail d4 CI" "$(field '.ci.failing[0] | "\(.state) \(.bucket) \(.link) \(.workflow)"')" "check run の変換"
assert_eq "ERROR fail s2 " "$(field '.ci.failing[3] | "\(.state) \(.bucket) \(.link) \(.workflow)"')" "コミットステータスの変換"
assert_eq "" "$(field '.ci.failing[4].link')" "target_url が null なら空文字"
checks "[$PASS_CHECK]" "" 0

t "REST: ワークフローの実行を取得できなくても、ワークフロー名を空にして続ける"
checks "[$FAIL_CHECK]" "" 1
rm "$(rest_file repos/o/r/actions/runs)"
run_rest
assert_eq 0 "$RC" "終了コード"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq "" "$(field '.ci.failing[0].workflow')" "ワークフロー名"
checks "[$PASS_CHECK]" "" 0

t "REST: 複数のスレッドを comment_ids の順に組み立てる"
write_pr OPEN MERGEABLE '[]' '[]' '[]'
jq -n --arg mine "$MINE" '[
  { id: 11, user: { login: "me", type: "User" }, body: "[P1] 1つめ", created_at: "2026-01-01T00:00:00Z", html_url: "u11" },
  { id: 21, user: { login: "me", type: "User" }, body: "[P2] 2つめ", created_at: "2026-01-01T00:01:00Z", html_url: "u21" },
  { id: 12, user: { login: "me", type: "User" }, body: ("直しました\n\n" + $mine), created_at: "2026-01-01T00:02:00Z", html_url: "u12" },
  { id: 22, user: { login: "me", type: "User" }, body: "まだです", created_at: "2026-01-01T00:03:00Z", html_url: "u22" }
]' >"$(rest_file repos/o/r/pulls/1/comments)"
echo '[
  { "resolved": true,  "outdated": true,  "path": "a.sh", "line": null, "comment_ids": [11, 12] },
  { "resolved": false, "outdated": false, "path": "b.sh", "line": 3,    "comment_ids": [21, 22] }
]' >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_verdict review_in_progress false "未解決スレッドあり"
assert_eq "11,12|21,22" "$(field '.threads | map(.comments | map(.databaseId) | join(",")) | join("|")')" "スレッドごとのコメント"
assert_eq "11,21" "$(field '.threads | map(.rootCommentId) | join(",")')" "rootCommentId"
assert_eq "true,false" "$(field '.threads | map(.lastCommentByMe) | join(",")')" "lastCommentByMe"
assert_eq "true b.sh 3" "$(field '.threads[0].isOutdated, .threads[1].path, .threads[1].line' | paste -sd' ')" "isOutdated・path・line"
assert_eq 1 "$(field .unresolvedThreadCount)" "unresolvedThreadCount"
assert_eq 2 "$(field .review.reviewerThreadCount)" "review.reviewerThreadCount"
assert_eq null "$(field '.threads[0].id')" "スレッドの ID は REST では取得できない"
assert_eq null "$(field .reviewDecision)" "reviewDecision は REST では取得できない"

t "REST: レビューコメントの一覧にないコメントだけのスレッドは除く"
echo '[
  { "resolved": false, "outdated": false, "path": "c.sh", "line": 1, "comment_ids": [99] },
  { "resolved": false, "outdated": false, "path": "b.sh", "line": 3, "comment_ids": [21, 99, 22] }
]' >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_verdict review_in_progress false "一覧にないコメント"
assert_eq "21,22" "$(field '.threads | map(.comments | map(.databaseId) | join(",")) | join("|")')" "一覧にないコメントとスレッドを除く"

done_testing
