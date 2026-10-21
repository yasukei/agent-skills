#!/usr/bin/env bash
# Tests for scripts/check-plugin-policy.py.
# Create policy-compliant manifests in a temporary directory, break one field at a time, and check that validation fails with the reason.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-plugin-policy.py"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Recreate the four policy-compliant manifests in $WORK.
# Arguments: the name in Claude's marketplace.json (default my-marketplace), and
# JSON to append to the plugin entry in Claude's marketplace.json and to plugin.json.
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

# Change one field with jq, without overwriting the input file in place.
edit_manifest() {
  jq "$2" "$WORK/$1" >"$WORK/edited.json" && mv "$WORK/edited.json" "$WORK/$1"
}

# Run the check and store the results in OUT, ERR and RC. The argument is the repository root (default $WORK)
run_check() {
  RC=0
  "$SCRIPT" "${1:-$WORK}" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

assert_fails_with() {
  assert_eq 1 "$RC" "exit status"
  assert_contains "$ERR" "$1" "stderr"
}

# ---------------------------------------------------------------------------
t "this repository's manifests"
run_check "$ROOT"
assert_eq 0 "$RC" "exit status ($ERR)"
assert_contains "$OUT" "plugin policy ok" "stdout"

# ---------------------------------------------------------------------------
t "checks the repository's manifests when given no argument"
# Even with $WORK (no manifests) as cwd, the repository is located from the script, not from cwd
RC=0
(cd "$WORK" && "$SCRIPT") >"$WORK/out" 2>"$WORK/err" || RC=$?
assert_eq 0 "$RC" "exit status ($(cat "$WORK/err"))"

# ---------------------------------------------------------------------------
t "policy-compliant manifests"
make_manifests
run_check
assert_eq 0 "$RC" "exit status ($ERR)"

# ---------------------------------------------------------------------------
t "marketplace.json name is the reserved name agent-skills"
make_manifests agent-skills
run_check
assert_fails_with ".claude-plugin/marketplace.json: name: 'agent-skills' is a reserved name and is rejected by claude.ai's marketplace sync"

# ---------------------------------------------------------------------------
t "marketplace.json name is the reserved name in different case"
make_manifests Agent-Skills
run_check
assert_fails_with ".claude-plugin/marketplace.json: name: 'Agent-Skills' is a reserved name"

# ---------------------------------------------------------------------------
t "plugin.json has version"
make_manifests my-marketplace "" ', "version": "1.0.0"'
run_check
assert_fails_with ".claude-plugin/plugin.json: version: this repository does not set version"
assert_contains "$ERR" "updates are not distributed" "reason"

# ---------------------------------------------------------------------------
t "marketplace.json plugin entry has version"
make_manifests my-marketplace ', "version": "1.0.0"'
run_check
assert_fails_with ".claude-plugin/marketplace.json: plugins[0] (agent-skills): version: this repository does not set version"

# ---------------------------------------------------------------------------
t "manifest is missing"
make_manifests
rm "$WORK/.claude-plugin/plugin.json"
run_check
assert_fails_with ".claude-plugin/plugin.json: not found"

# ---------------------------------------------------------------------------
t "cannot parse as JSON"
make_manifests
echo '{' >"$WORK/.claude-plugin/marketplace.json"
run_check
assert_fails_with ".claude-plugin/marketplace.json: cannot parse as JSON"

# ---------------------------------------------------------------------------
t "does not crash when name is not a string"
make_manifests
sed -i 's/"name": "my-marketplace"/"name": ["agent-skills"]/' "$WORK/.claude-plugin/marketplace.json"
run_check
assert_eq 0 "$RC" "exit status ($ERR)"

# ---------------------------------------------------------------------------
t "not readable as UTF-8"
make_manifests
printf '\xff\xfe' >"$WORK/.claude-plugin/plugin.json"
run_check
assert_fails_with ".claude-plugin/plugin.json: cannot parse as JSON"

# ---------------------------------------------------------------------------
for rel in plugin.json .agents/plugins/marketplace.json; do
  t "$rel is missing"
  make_manifests
  rm "$WORK/$rel"
  run_check
  assert_fails_with "$rel: not found"

  t "$rel is invalid JSON"
  make_manifests
  echo '{' >"$WORK/$rel"
  run_check
  assert_fails_with "$rel: cannot parse as JSON"

  t "$rel is not an object"
  make_manifests
  echo '[]' >"$WORK/$rel"
  run_check
  assert_fails_with "$rel: not a JSON object"

  t "$rel has version"
  make_manifests
  if [ "$rel" = plugin.json ]; then
    edit_manifest "$rel" '.version = "1.0.0"'
  else
    edit_manifest "$rel" '.plugins[0].version = "1.0.0"'
  fi
  run_check
  assert_fails_with "version: this repository does not set version"
  assert_contains "$ERR" "$rel:" "target file"
done

# ---------------------------------------------------------------------------
for field in name description; do
  t "$field differs between the two formats"
  make_manifests
  edit_manifest plugin.json ".$field = \"different\""
  run_check
  assert_fails_with "plugin.json: $field: must match the $field in .claude-plugin/plugin.json"

  for rel in plugin.json .claude-plugin/plugin.json; do
    for value in 'null' '""' '"   "' '[]'; do
      t "$rel $field is empty or not a string: $value"
      make_manifests
      edit_manifest "$rel" ".$field = $value"
      run_check
      assert_fails_with "$rel: $field: must be a non-empty string"
    done
  done
done

# ---------------------------------------------------------------------------
for rel in .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  t "$rel entry name does not match the plugin definition"
  make_manifests
  edit_manifest "$rel" '.plugins[0].name = "different"'
  run_check
  assert_fails_with "$rel: plugins[0].name: must match the name in the plugin definition"

  for value in 'null' '[]' '{}'; do
    t "$rel plugins is empty or not an array: $value"
    make_manifests
    edit_manifest "$rel" ".plugins = $value"
    run_check
    assert_fails_with "$rel: plugins: must be a non-empty array"
  done

  t "$rel entry is not an object"
  make_manifests
  edit_manifest "$rel" '.plugins = [null]'
  run_check
  assert_fails_with "$rel: plugins[0]: must be an object"
done

# ---------------------------------------------------------------------------
rel=.agents/plugins/marketplace.json
for field in installation authentication; do
  t "Codex policy.$field is missing"
  make_manifests
  edit_manifest "$rel" "del(.plugins[0].policy.$field)"
  run_check
  assert_fails_with "$rel: plugins[0].policy.$field:"

  t "Codex policy.$field is invalid"
  make_manifests
  edit_manifest "$rel" ".plugins[0].policy.$field = []"
  run_check
  assert_fails_with "$rel: plugins[0].policy.$field:"
done
for value in 'null' '[]' '""'; do
  t "Codex policy is not an object: $value"
  make_manifests
  edit_manifest "$rel" ".plugins[0].policy = $value"
  run_check
  assert_fails_with "$rel: plugins[0].policy.installation:"
  assert_contains "$ERR" "plugins[0].policy.authentication:" "authentication policy error"
done
for value in 'null' '""' '"   "' '[]'; do
  t "Codex category is empty or not a string: $value"
  make_manifests
  edit_manifest "$rel" ".plugins[0].category = $value"
  run_check
  assert_fails_with "$rel: plugins[0].category: must be a non-empty string"
done

t "checks the policy of every Codex entry"
make_manifests
edit_manifest "$rel" '.plugins += [.plugins[0]] | del(.plugins[1].policy)'
run_check
assert_fails_with "$rel: plugins[1].policy.installation:"

# ---------------------------------------------------------------------------
t "reports every problem when there are several"
make_manifests agent-skills ', "version": "1.0.0"' ', "version": "1.0.0"'
run_check
assert_fails_with "name: 'agent-skills' is a reserved name"
assert_contains "$ERR" "plugins[0] (agent-skills): version" "entry version"
assert_contains "$ERR" "plugin.json: version" "plugin.json version"
assert_contains "$ERR" "3 problem(s) found" "count"

# ---------------------------------------------------------------------------
t "invalid argument"
run_check "$WORK/no-such-dir"
assert_fails_with "directory not found"

done_testing
