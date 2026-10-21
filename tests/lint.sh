#!/usr/bin/env bash
# Run bash -n and shellcheck on scripts/*.sh and skills/*/scripts/*.sh (and the tests themselves).
set -euo pipefail

cd "$(dirname "$0")/.."

# Ignore patterns that match no file instead of passing the pattern string itself
shopt -s nullglob
files=(scripts/*.sh skills/*/scripts/*.sh tests/*.sh tests/fake-bin/gh)

for f in "${files[@]}"; do
  bash -n "$f"
done
echo "bash -n: ${#files[@]} files ok"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found" >&2
  exit 1
fi
# lib.sh is meant to be sourced, so specify the shell explicitly
shellcheck --shell=bash "${files[@]}"
echo "shellcheck: ${#files[@]} files ok"
