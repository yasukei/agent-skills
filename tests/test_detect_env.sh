#!/usr/bin/env bash
# Tests for skills/setup-dev-env/scripts/detect.sh: builds repositories in a temporary directory and checks the report.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/setup-dev-env/scripts/detect.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fake tools: each prints a fixed version, so the tools section does not depend on this machine
FAKE="$WORK/bin"
mkdir -p "$FAKE"
fake_tool() {
  printf '#!/bin/sh\necho "%s"\n' "$2" >"$FAKE/$1"
  chmod +x "$FAKE/$1"
}
fake_tool node v20.11.1
fake_tool pnpm 9.1.0
# A shim-like cargo that reports where and with which auto-download switches it was run
# shellcheck disable=SC2016 # expanded by the fake, not here
printf '#!/bin/sh\necho "pwd=$PWD go=$GOTOOLCHAIN rustup=$RUSTUP_AUTO_INSTALL corepack=$COREPACK_ENABLE_NETWORK"\n' >"$FAKE/cargo"
chmod +x "$FAKE/cargo"
# Keep the basic commands the script needs, but no real node / python / jq from this machine
BASE="$WORK/base"
mkdir -p "$BASE"
for cmd in sed awk find sort basename head grep uname timeout cat env; do
  real="$(command -v "$cmd")" && ln -s "$real" "$BASE/$cmd"
done

# detect <dir> [VAR=value]...: runs the script with a controlled environment; stores OUT and RC
detect() {
  local d="$1"
  shift
  RC=0
  OUT="$(env -i PATH="$FAKE:$BASE" HOME="$WORK/home" SETUP_DEV_ENV_SBX_FILE="$WORK/none" "$@" \
    /bin/bash "$SCRIPT" "$d" 2>"$WORK/err")" || RC=$?
}

# A real jq or python3 is needed to read package.json; link whichever exists
for cmd in jq python3; do
  real="$(command -v "$cmd")" && ln -s "$real" "$BASE/$cmd"
done

# ---------------------------------------------------------------------------
t "node and pnpm project: pins from every source, lockfile, packageManager, workspaces"
R="$WORK/node"
mkdir -p "$R/packages/app" "$R/node_modules/dep" "$R/.github/workflows"
echo "20.11.1" >"$R/.nvmrc"
printf '# comment\nnodejs 20.11.1\npython 3.12.4\n' >"$R/.tool-versions"
cat >"$R/package.json" <<'EOF'
{"packageManager": "pnpm@9.1.0", "engines": {"node": ">=20"}, "workspaces": ["packages/*"],
 "scripts": {"test": "vitest run"}}
EOF
echo '{}' >"$R/packages/app/package.json"
echo '{}' >"$R/node_modules/dep/package.json"
echo 'lockfileVersion: 9.0' >"$R/pnpm-lock.yaml"
echo 'on: push' >"$R/.github/workflows/ci.yml"
touch "$R/.env.example"
detect "$R"
assert_eq 0 "$RC" "exit status ($(cat "$WORK/err"))"
assert_contains "$OUT" "kind: host" "environment"
assert_contains "$OUT" "node: 20.11.1 (.nvmrc)" ".nvmrc"
assert_contains "$OUT" "node: 20.11.1 (.tool-versions)" ".tool-versions nodejs"
assert_contains "$OUT" "python: 3.12.4 (.tool-versions)" ".tool-versions python"
assert_contains "$OUT" "node: >=20 (package.json engines.node)" "engines"
assert_contains "$OUT" "packageManager: pnpm@9.1.0 (package.json)" "packageManager"
assert_contains "$OUT" "pnpm: pnpm-lock.yaml" "lockfile"
assert_contains "$OUT" "packages/app/package.json" "workspace manifest"
assert_contains "$OUT" 'workspaces: ["packages/*"]' "workspaces"
assert_contains "$OUT" "vitest run" "scripts"
assert_contains "$OUT" ".github/workflows/ci.yml" "CI workflow"
assert_contains "$OUT" ".env.example" "env example"
assert_contains "$OUT" "node: v20.11.1 ($FAKE/node)" "node tool"
assert_contains "$OUT" "pnpm: 9.1.0 ($FAKE/pnpm)" "pnpm tool"
assert_contains "$OUT" "uv: missing" "missing tool"
case "$OUT" in
  *node_modules*) fail "node_modules must be skipped" ;;
  *) pass ;;
esac

t "tools are probed from a neutral directory with auto-download off"
assert_contains "$OUT" "cargo: pwd=/ go=local rustup=0 corepack=0 ($FAKE/cargo)" "probe environment"

t "python project: .python-version, requires-python, poetry, mise, uv.lock"
R="$WORK/py"
mkdir -p "$R"
echo "3.12" >"$R/.python-version"
cat >"$R/pyproject.toml" <<'EOF'
[project]  # metadata
name = "x"
requires-python = ">=3.11"  # comment

[tool.poetry.dependencies]
python = "^3.11"
EOF
printf '[tools] # runtimes\nnode = { version = "22", postinstall = "x" }\npython = ["3.12", "3.11"]\ngo = { path = "x" }\n' >"$R/mise.toml"
touch "$R/uv.lock" "$R/requirements-dev.txt"
detect "$R"
assert_contains "$OUT" "python: 3.12 (.python-version)" ".python-version"
assert_contains "$OUT" "python: >=3.11 (pyproject.toml requires-python)" "requires-python"
assert_contains "$OUT" "python: ^3.11 (pyproject.toml tool.poetry python)" "poetry python"
assert_contains "$OUT" "node: 22 (mise.toml [tools])" "mise node"
assert_contains "$OUT" "python: 3.12, 3.11 (mise.toml [tools])" "mise python list"
assert_contains "$OUT" 'go: { path = "x" } (mise.toml [tools])' "inline table without version, as written"
assert_contains "$OUT" "uv: uv.lock" "uv lock"
assert_contains "$OUT" "requirements-dev.txt" "requirements"

t "yarn classic and berry are told apart"
R="$WORK/yarn"
mkdir -p "$R/classic" "$R/berry"
echo '# yarn lockfile v1' >"$R/classic/yarn.lock"
printf '__metadata:\n  version: 8\n' >"$R/berry/yarn.lock"
detect "$R"
assert_contains "$OUT" "yarn (classic): classic/yarn.lock" "classic"
assert_contains "$OUT" "yarn (berry): berry/yarn.lock" "berry"

t "other ecosystems: go.mod, rust-toolchain.toml, .ruby-version, .sdkmanrc"
R="$WORK/other"
mkdir -p "$R"
printf 'module x\n\ngo 1.22\n\ntoolchain go1.22.3\n' >"$R/go.mod"
printf '[toolchain]\nchannel = "1.79.0"\n' >"$R/rust-toolchain.toml"
echo "3.3.0" >"$R/.ruby-version"
echo "java=21.0.2-tem" >"$R/.sdkmanrc"
echo '{}' >"$R/packages.lock.json"
detect "$R"
assert_contains "$OUT" "go: 1.22 (go.mod go, minimum)" "go"
assert_contains "$OUT" "go: go1.22.3 (go.mod toolchain)" "toolchain"
assert_contains "$OUT" "rust: 1.79.0 (rust-toolchain.toml)" "rust"
assert_contains "$OUT" "ruby: 3.3.0 (.ruby-version)" "ruby"
assert_contains "$OUT" "java: 21.0.2-tem (.sdkmanrc)" "java"
assert_contains "$OUT" "nuget: packages.lock.json" "nuget lock"

t "devEngines.runtime: the node entry's version range, as an object or in an array"
R="$WORK/dev"
mkdir -p "$R/obj" "$R/arr" "$R/other"
echo '{"devEngines": {"runtime": {"name": "node", "version": ">=20"}}}' >"$R/obj/package.json"
echo '{"devEngines": {"runtime": [{"name": "bun", "version": "1"}, {"name": "node", "version": "^22"}]}}' \
  >"$R/arr/package.json"
echo '{"devEngines": {"runtime": {"name": "deno", "version": "2"}}}' >"$R/other/package.json"
detect "$R/obj"
assert_contains "$OUT" "node: >=20 (package.json devEngines.runtime)" "object"
detect "$R/arr"
assert_contains "$OUT" "node: ^22 (package.json devEngines.runtime)" "array"
detect "$R/other"
case "$OUT" in
  *devEngines*) fail "a non-node runtime must not be reported as node" ;;
  *) pass ;;
esac

t "environment: sbx from SANDBOX_NAME, cloud from CLAUDE_CODE_REMOTE, nvm from NVM_DIR"
mkdir -p "$WORK/nvm"
echo ': nvm' >"$WORK/nvm/nvm.sh"
detect "$WORK/other" SANDBOX_NAME=box NVM_DIR="$WORK/nvm"
assert_contains "$OUT" "kind: sbx (sandbox box)" "sbx"
assert_contains "$OUT" "nvm: installed ($WORK/nvm/nvm.sh" "nvm"
detect "$WORK/other" CLAUDE_CODE_REMOTE=true
assert_contains "$OUT" "kind: cloud (Claude Code on the web)" "cloud"
assert_contains "$OUT" "nvm: missing" "no nvm"

t "empty repository: every section present, nothing guessed"
mkdir -p "$WORK/empty"
detect "$WORK/empty"
assert_eq 0 "$RC" "exit status"
for section in environment "version pins" "package managers" manifests "setup hints" tools; do
  assert_contains "$OUT" "## $section" "section $section"
done
case "$OUT" in
  *"(.nvmrc)"* | *"(package.json"*) fail "pins reported for an empty repository" ;;
  *) pass ;;
esac

t "not a directory: exit status 2"
detect "$WORK/does-not-exist"
assert_eq 2 "$RC" "exit status"

done_testing
