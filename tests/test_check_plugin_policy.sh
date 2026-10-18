#!/usr/bin/env bash
# scripts/check-plugin-policy.py のテスト。
# 一時ディレクトリに方針に沿ったマニフェストを作り、1か所ずつ壊して検証が失敗し、理由が出力されることを確かめる。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-plugin-policy.py"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 方針に沿ったマニフェストを $WORK/.claude-plugin に作り直す。
# 引数は marketplace.json の name（省略時は my-marketplace）と、marketplace.json のプラグインエントリ・
# plugin.json に足す JSON（省略時は何も足さない）
make_manifests() {
  local market_name="${1:-my-marketplace}" entry_extra="${2:-}" plugin_extra="${3:-}"
  rm -rf "$WORK/.claude-plugin"
  mkdir -p "$WORK/.claude-plugin"
  cat >"$WORK/.claude-plugin/marketplace.json" <<EOF
{
  "name": "$market_name",
  "owner": {"name": "someone"},
  "plugins": [
    {"name": "agent-skills", "source": "./"$entry_extra}
  ]
}
EOF
  cat >"$WORK/.claude-plugin/plugin.json" <<EOF
{
  "name": "agent-skills"$plugin_extra
}
EOF
}

# 検証を実行し、OUT・ERR・RC に結果を入れる。引数はリポジトリのルート（省略時は $WORK）
run_check() {
  RC=0
  "$SCRIPT" "${1:-$WORK}" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

assert_fails_with() {
  assert_eq 1 "$RC" "終了コード"
  assert_contains "$ERR" "$1" "エラー出力"
}

# ---------------------------------------------------------------------------
t "このリポジトリのマニフェスト"
run_check "$ROOT"
assert_eq 0 "$RC" "終了コード（$ERR）"
assert_contains "$OUT" "plugin policy ok" "標準出力"

# ---------------------------------------------------------------------------
t "引数なしでリポジトリのマニフェストを検証する"
# マニフェストのない $WORK を cwd にしても、cwd ではなくスクリプトの場所を基準にリポジトリを検証する
RC=0
(cd "$WORK" && "$SCRIPT") >"$WORK/out" 2>"$WORK/err" || RC=$?
assert_eq 0 "$RC" "終了コード（$(cat "$WORK/err")）"

# ---------------------------------------------------------------------------
t "方針に沿ったマニフェスト"
make_manifests
run_check
assert_eq 0 "$RC" "終了コード（$ERR）"

# ---------------------------------------------------------------------------
t "marketplace.json の name が予約名 agent-skills"
make_manifests agent-skills
run_check
assert_fails_with ".claude-plugin/marketplace.json: name: 'agent-skills' は予約名で、claude.ai のマーケットプレイス同期で拒否されます"

# ---------------------------------------------------------------------------
t "marketplace.json の name が大文字小文字違いの予約名"
make_manifests Agent-Skills
run_check
assert_fails_with ".claude-plugin/marketplace.json: name: 'Agent-Skills' は予約名で"

# ---------------------------------------------------------------------------
t "plugin.json に version がある"
make_manifests my-marketplace "" ', "version": "1.0.0"'
run_check
assert_fails_with ".claude-plugin/plugin.json: version: このリポジトリでは version を書きません"
assert_contains "$ERR" "更新が配布されません" "理由"

# ---------------------------------------------------------------------------
t "marketplace.json のプラグインエントリに version がある"
make_manifests my-marketplace ', "version": "1.0.0"'
run_check
assert_fails_with ".claude-plugin/marketplace.json: plugins[0]（agent-skills）: version: このリポジトリでは version を書きません"

# ---------------------------------------------------------------------------
t "マニフェストがない"
make_manifests
rm "$WORK/.claude-plugin/plugin.json"
run_check
assert_fails_with ".claude-plugin/plugin.json: ありません"

# ---------------------------------------------------------------------------
t "JSON として解析できない"
make_manifests
echo '{' >"$WORK/.claude-plugin/marketplace.json"
run_check
assert_fails_with ".claude-plugin/marketplace.json: JSON として解析できません"

# ---------------------------------------------------------------------------
t "name が文字列でなくても落ちない"
make_manifests
sed -i 's/"name": "my-marketplace"/"name": ["agent-skills"]/' "$WORK/.claude-plugin/marketplace.json"
run_check
assert_eq 0 "$RC" "終了コード（$ERR）"

# ---------------------------------------------------------------------------
t "UTF-8 として読めない"
make_manifests
printf '\xff\xfe' >"$WORK/.claude-plugin/plugin.json"
run_check
assert_fails_with ".claude-plugin/plugin.json: JSON として解析できません"

# ---------------------------------------------------------------------------
t "問題が複数あればすべて出力する"
make_manifests agent-skills ', "version": "1.0.0"' ', "version": "1.0.0"'
run_check
assert_fails_with "name: 'agent-skills' は予約名"
assert_contains "$ERR" "plugins[0]（agent-skills）: version" "エントリの version"
assert_contains "$ERR" "plugin.json: version" "plugin.json の version"
assert_contains "$ERR" "3 件の問題があります" "件数"

# ---------------------------------------------------------------------------
t "不正な引数"
run_check "$WORK/no-such-dir"
assert_fails_with "ディレクトリがありません"

done_testing
