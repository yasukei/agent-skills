#!/usr/bin/env bash
# Report what a repository declares for its development environment and what this machine has.
#   detect.sh [DIR]   (DIR defaults to the current directory)
#
# Read-only: it changes nothing and installs nothing. Sections (each line is "key: value (source)"):
#   ## environment       sbx sandbox, cloud session or host, and the OS
#   ## version pins      runtime versions the repository asks for, one line per source
#   ## package managers  managers implied by lockfiles and package.json packageManager
#   ## manifests         dependency manifests up to 3 levels deep (workspaces, monorepos)
#   ## setup hints       files that document or automate setup and tests (CI, Makefile, ...)
#   ## tools             tools on PATH with their versions, "missing" otherwise. Probed from a neutral
#                        directory with auto-download switches off, so version-aware shims (corepack, rustup,
#                        go, mise, a yarnPath) neither act on the repository's pins nor download anything:
#                        the lines say what the machine has, not what the pins resolve to
# Several pins for one runtime are all printed; deciding which one wins is the caller's job
# (see references/version-pins.md), because the right answer depends on the repository.
#
# SETUP_DEV_ENV_SBX_FILE overrides the sbx persistent environment file path (for tests).
set -uo pipefail

dir="${1:-.}"
if [ ! -d "$dir" ]; then
  echo "$0: not a directory: $dir" >&2
  exit 2
fi
cd "$dir" || exit 2

sbx_file="${SETUP_DEV_ENV_SBX_FILE:-/etc/sandbox-persistent.sh}"

# Print the first line of a file without surrounding whitespace, skipping comments and blank lines
first_value() {
  sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | sed -n '/./{p;q;}'
}

# Read a JSON field (jq syntax, e.g. .engines.node) with jq, else python3; prints nothing when absent
json_get() {
  local file="$1" path="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$path // empty | if type == \"string\" then . else tojson end" "$file" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I - "$file" "$path" <<'PY' 2>/dev/null
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for key in sys.argv[2].lstrip(".").split("."):
    data = data.get(key) if isinstance(data, dict) else None
if data is not None:
    print(data if isinstance(data, str) else json.dumps(data))
PY
  fi
}

# Print "key = value" values inside a TOML [section] for the given key, quotes and brackets removed.
# Header comments are ignored. An inline table prints its version field (node = { version = "22" }),
# else the table as written, so the caller can read it.
toml_get() {
  local file="$1" section="$2" key="$3"
  awk -v section="[$section]" -v key="$key" '
    /^[[:space:]]*\[/ { sub(/#.*/, ""); gsub(/[[:space:]]/, ""); in_section = ($0 == section); next }
    in_section {
      line = $0
      sub(/#.*/, "", line)
      if (match(line, "^[[:space:]]*\"?" key "\"?[[:space:]]*=")) {
        value = substr(line, RLENGTH + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        if (value ~ /^\{/) {
          if (match(value, /version[[:space:]]*=[[:space:]]*["\047][^"\047]*["\047]/)) {
            value = substr(value, RSTART, RLENGTH)
            sub(/^version[[:space:]]*=[[:space:]]*/, "", value)
          } else {
            print value
            next
          }
        }
        gsub(/[\"\047\[\]]/, "", value)
        print value
      }
    }' "$file"
}

# Print the version range of the node entry in package.json devEngines.runtime (an object or an array)
devengines_node() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.devEngines.runtime // empty | if type == "array" then .[] else . end
      | select(type == "object" and .name == "node") | .version // empty' package.json 2>/dev/null | head -1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I - <<'PY' 2>/dev/null
import json
runtime = (json.load(open("package.json", encoding="utf-8")).get("devEngines") or {}).get("runtime")
for entry in runtime if isinstance(runtime, list) else [runtime]:
    if isinstance(entry, dict) and entry.get("name") == "node" and entry.get("version"):
        print(entry["version"])
        break
PY
  fi
}

pin() {
  # pin <runtime> <value> <source>
  [ -n "$2" ] && echo "$1: $2 ($3)"
}

echo "## environment"
if [ -n "${SANDBOX_NAME:-}" ] || [ -f "$sbx_file" ]; then
  echo "kind: sbx (sandbox ${SANDBOX_NAME:-unknown})"
  [ -f "$sbx_file" ] && echo "persistent-env: $sbx_file"
  if [ -d /run/sandbox/source ]; then echo "git-mode: clone"; else echo "git-mode: direct"; fi
elif [ "${CLAUDE_CODE_REMOTE:-}" = true ]; then
  echo "kind: cloud (Claude Code on the web)"
elif [ -n "${CODEX_SANDBOX:-}" ] || [ -n "${CODEX_SANDBOX_NETWORK_DISABLED:-}" ]; then
  echo "kind: codex sandbox${CODEX_SANDBOX_NETWORK_DISABLED:+ (network disabled)}"
else
  echo "kind: host"
fi
echo "os: $(uname -s) $(uname -m)"

echo "## version pins"
for f in .nvmrc .node-version; do
  [ -f "$f" ] && pin node "$(first_value "$f")" "$f"
done
[ -f .python-version ] && pin python "$(first_value .python-version)" .python-version
if [ -f .tool-versions ]; then
  while read -r tool version _; do
    case "$tool" in
      nodejs | node) pin node "$version" .tool-versions ;;
      python | golang | ruby | java | rust) pin "${tool/golang/go}" "$version" .tool-versions ;;
    esac
  done < <(sed -e 's/#.*//' .tool-versions)
fi
for f in mise.toml .mise.toml; do
  [ -f "$f" ] || continue
  for tool in node python go ruby java rust; do
    pin "$tool" "$(toml_get "$f" tools "$tool" | head -1)" "$f [tools]"
  done
done
if [ -f package.json ]; then
  pin node "$(json_get package.json .engines.node)" "package.json engines.node"
  pin node "$(json_get package.json .volta.node)" "package.json volta.node"
  pin node "$(devengines_node)" "package.json devEngines.runtime"
fi
if [ -f pyproject.toml ]; then
  pin python "$(toml_get pyproject.toml project requires-python)" "pyproject.toml requires-python"
  pin python "$(toml_get pyproject.toml tool.poetry.dependencies python)" "pyproject.toml tool.poetry python"
fi
[ -f runtime.txt ] && pin python "$(first_value runtime.txt)" runtime.txt
if [ -f go.mod ]; then
  pin go "$(awk '$1 == "go" { print $2; exit }' go.mod)" "go.mod go, minimum"
  pin go "$(awk '$1 == "toolchain" { print $2; exit }' go.mod)" "go.mod toolchain"
fi
[ -f rust-toolchain.toml ] && pin rust "$(toml_get rust-toolchain.toml toolchain channel)" rust-toolchain.toml
[ -f rust-toolchain ] && pin rust "$(first_value rust-toolchain)" rust-toolchain
[ -f .ruby-version ] && pin ruby "$(first_value .ruby-version)" .ruby-version
[ -f .java-version ] && pin java "$(first_value .java-version)" .java-version
[ -f .sdkmanrc ] && pin java "$(sed -n 's/^java=//p' .sdkmanrc | head -1)" .sdkmanrc
[ -f global.json ] && pin dotnet "$(json_get global.json .sdk.version)" "global.json sdk.version"

echo "## package managers"
[ -f package.json ] && pin packageManager "$(json_get package.json .packageManager)" "package.json"
find . -maxdepth 3 \( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name vendor \) -prune -o \
  -type f \( -name package-lock.json -o -name npm-shrinkwrap.json -o -name pnpm-lock.yaml -o -name yarn.lock \
  -o -name bun.lockb -o -name bun.lock -o -name uv.lock -o -name poetry.lock -o -name pdm.lock \
  -o -name Pipfile.lock -o -name Cargo.lock -o -name go.sum -o -name Gemfile.lock -o -name composer.lock -o -name packages.lock.json \) \
  -print 2>/dev/null | sed 's|^\./||' | sort | while read -r lock; do
  case "$(basename "$lock")" in
    package-lock.json | npm-shrinkwrap.json) m=npm ;;
    pnpm-lock.yaml) m=pnpm ;;
    yarn.lock) if grep -q '^__metadata:' "$lock"; then m="yarn (berry)"; else m="yarn (classic)"; fi ;;
    bun.lockb | bun.lock) m=bun ;;
    uv.lock) m=uv ;;
    poetry.lock) m=poetry ;;
    pdm.lock) m=pdm ;;
    Pipfile.lock) m=pipenv ;;
    Cargo.lock) m=cargo ;;
    go.sum) m=go ;;
    Gemfile.lock) m=bundler ;;
    composer.lock) m=composer ;;
    packages.lock.json) m=nuget ;;
  esac
  echo "$m: $lock"
done

echo "## manifests"
find . -maxdepth 3 \( -name node_modules -o -name .git -o -name .venv -o -name venv -o -name vendor \
  -o -name dist -o -name build -o -name target \) -prune -o -type f \( -name package.json -o -name pyproject.toml \
  -o -name 'requirements*.txt' -o -name setup.py -o -name setup.cfg -o -name Pipfile -o -name go.mod \
  -o -name Cargo.toml -o -name Gemfile -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts \
  -o -name composer.json -o -name deno.json -o -name deno.jsonc -o -name pnpm-workspace.yaml \) \
  -print 2>/dev/null | sed 's|^\./||' | sort
[ -f package.json ] && pin workspaces "$(json_get package.json .workspaces)" "package.json"

echo "## setup hints"
for f in README.md README.rst README CONTRIBUTING.md AGENTS.md CLAUDE.md Makefile justfile Taskfile.yml \
  Taskfile.yaml tox.ini noxfile.py .pre-commit-config.yaml .devcontainer/devcontainer.json devcontainer.json \
  docker-compose.yml docker-compose.yaml compose.yml compose.yaml .env.example .env.sample .env.template \
  setup.sh scripts/setup.sh scripts/bootstrap bin/setup; do
  [ -e "$f" ] && echo "$f"
done
find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sed 's|^\./||' | sort
[ -f package.json ] && pin scripts "$(json_get package.json .scripts)" "package.json"

echo "## tools"
run_version() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 10 "$@" 2>&1 | head -1
  else
    "$@" 2>&1 | head -1
  fi
}
# Run from / with auto-download off: inside the repository, shims would act on its pins (see the header)
probe_env=(GOTOOLCHAIN=local RUSTUP_AUTO_INSTALL=0 COREPACK_ENABLE_NETWORK=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  COREPACK_ENABLE_AUTO_PIN=0 MISE_AUTO_INSTALL=0)
for tool in node npm pnpm yarn bun deno corepack python3 python uv poetry pdm pipenv pipx pyenv \
  mise fnm volta asdf go cargo rustup java ruby bundle docker; do
  if path="$(command -v "$tool" 2>/dev/null)"; then
    case "$tool" in
      go) version="$(cd / && run_version env "${probe_env[@]}" go version)" ;;
      java) version="$(cd / && run_version env "${probe_env[@]}" java -version)" ;;
      *) version="$(cd / && run_version env "${probe_env[@]}" "$tool" --version)" ;;
    esac
    echo "$tool: ${version:-unknown version} ($path)"
  else
    echo "$tool: missing"
  fi
done
# Shell-function managers are invisible to command -v in a fresh non-interactive shell
nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
if [ -s "$nvm_sh" ]; then echo "nvm: installed ($nvm_sh; source it in each shell)"; else echo "nvm: missing"; fi
sdk_init="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
if [ -s "$sdk_init" ]; then echo "sdkman: installed ($sdk_init; source it in each shell)"; else echo "sdkman: missing"; fi
