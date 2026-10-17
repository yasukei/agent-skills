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

# gh api graphql の出力を作る。引数はレビュースレッドの最後のコメント本文
write_graphql() {
  jq -n --arg last "$1" '{
    data: { repository: { pullRequest: {
      url: "https://github.com/o/r/pull/1",
      state: "OPEN", isDraft: false, mergeable: "MERGEABLE", reviewDecision: null,
      author: { login: "me" }, headRefName: "feat/1-x", baseRefName: "main",
      reviews: { nodes: [] },
      reviewThreads: { nodes: [ {
        id: "T1", isResolved: false, isOutdated: false, path: "a.sh", line: 1,
        comments: { nodes: [
          { databaseId: 1, author: { login: "me" }, body: "[P2] 直してください", createdAt: "2026-01-01T00:00:00Z", url: "u1" },
          { databaseId: 2, author: { login: "me" }, body: $last, createdAt: "2026-01-01T00:01:00Z", url: "u2" }
        ] }
      } ] },
      comments: { nodes: [] }
    } } }
  }' >"$FAKE_GRAPHQL"
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

done_testing
