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

# 方針に沿った4つのマニフェストを $WORK に作り直す。
# 引数は Claude の marketplace.json の name（省略時は my-marketplace）と、
# Claude の marketplace.json のプラグインエントリ・plugin.json に足す JSON。
make_manifests() {
  local market_name="${1:-my-marketplace}" entry_extra="${2:-}" plugin_extra="${3:-}"
  rm -rf "$WORK/.claude-plugin" "$WORK/.agents" "$WORK/plugin.json"
  mkdir -p "$WORK/.claude-plugin" "$WORK/.agents/plugins"
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
  "name": "agent-skills",
  "description": "Shared skills"$plugin_extra
}
EOF
  cat >"$WORK/plugin.json" <<'EOF'
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "agent-skills",
  "description": "Shared skills"
}
EOF
  cat >"$WORK/.agents/plugins/marketplace.json" <<'EOF'
{
  "name": "my-marketplace",
  "plugins": [{
    "name": "agent-skills",
    "source": {"source": "local", "path": "./"},
    "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
    "category": "Productivity"
  }]
}
EOF
}

# jq で1項目を変更する。入力ファイルを直接上書きしない。
edit_manifest() {
  jq "$2" "$WORK/$1" >"$WORK/edited.json" && mv "$WORK/edited.json" "$WORK/$1"
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
for rel in plugin.json .agents/plugins/marketplace.json; do
  t "$rel がない"
  make_manifests
  rm "$WORK/$rel"
  run_check
  assert_fails_with "$rel: ありません"

  t "$rel が不正な JSON"
  make_manifests
  echo '{' >"$WORK/$rel"
  run_check
  assert_fails_with "$rel: JSON として解析できません"

  t "$rel がオブジェクトでない"
  make_manifests
  echo '[]' >"$WORK/$rel"
  run_check
  assert_fails_with "$rel: JSON のオブジェクトになっていません"

  t "$rel に version がある"
  make_manifests
  if [ "$rel" = plugin.json ]; then
    edit_manifest "$rel" '.version = "1.0.0"'
  else
    edit_manifest "$rel" '.plugins[0].version = "1.0.0"'
  fi
  run_check
  assert_fails_with "version: このリポジトリでは version を書きません"
  assert_contains "$ERR" "$rel:" "対象のファイル"
done

# ---------------------------------------------------------------------------
for field in name description; do
  t "両形式の $field が一致しない"
  make_manifests
  edit_manifest plugin.json ".$field = \"different\""
  run_check
  assert_fails_with "plugin.json: $field: .claude-plugin/plugin.json の $field と一致させてください"

  for rel in plugin.json .claude-plugin/plugin.json; do
    for value in 'null' '""' '"   "' '[]'; do
      t "$rel の $field が空または文字列でない: $value"
      make_manifests
      edit_manifest "$rel" ".$field = $value"
      run_check
      assert_fails_with "$rel: $field: 空でない文字列を指定してください"
    done
  done
done

# ---------------------------------------------------------------------------
for rel in .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  t "$rel のエントリ名がプラグイン定義と一致しない"
  make_manifests
  edit_manifest "$rel" '.plugins[0].name = "different"'
  run_check
  assert_fails_with "$rel: plugins[0].name: プラグイン定義の name と一致させてください"

  for value in 'null' '[]' '{}'; do
    t "$rel の plugins が空または配列でない: $value"
    make_manifests
    edit_manifest "$rel" ".plugins = $value"
    run_check
    assert_fails_with "$rel: plugins: 空でない配列にしてください"
  done

  t "$rel のエントリがオブジェクトでない"
  make_manifests
  edit_manifest "$rel" '.plugins = [null]'
  run_check
  assert_fails_with "$rel: plugins[0]: オブジェクトにしてください"
done

# ---------------------------------------------------------------------------
rel=.agents/plugins/marketplace.json
for field in installation authentication; do
  t "Codex の policy.$field がない"
  make_manifests
  edit_manifest "$rel" "del(.plugins[0].policy.$field)"
  run_check
  assert_fails_with "$rel: plugins[0].policy.$field:"

  t "Codex の policy.$field が不正"
  make_manifests
  edit_manifest "$rel" ".plugins[0].policy.$field = []"
  run_check
  assert_fails_with "$rel: plugins[0].policy.$field:"
done
for value in 'null' '[]' '""'; do
  t "Codex の policy がオブジェクトでない: $value"
  make_manifests
  edit_manifest "$rel" ".plugins[0].policy = $value"
  run_check
  assert_fails_with "$rel: plugins[0].policy.installation:"
  assert_contains "$ERR" "plugins[0].policy.authentication:" "認証ポリシーのエラー"
done
for value in 'null' '""' '"   "' '[]'; do
  t "Codex の category が空または文字列でない: $value"
  make_manifests
  edit_manifest "$rel" ".plugins[0].category = $value"
  run_check
  assert_fails_with "$rel: plugins[0].category: 空でない文字列を指定してください"
done

t "Codex の各エントリのポリシーを検証する"
make_manifests
edit_manifest "$rel" '.plugins += [.plugins[0]] | del(.plugins[1].policy)'
run_check
assert_fails_with "$rel: plugins[1].policy.installation:"

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
