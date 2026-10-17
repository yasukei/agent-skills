#!/usr/bin/env bash
# scripts/*.sh と skills/*/scripts/*.sh（とテスト自身）に bash -n と shellcheck をかける。
set -euo pipefail

cd "$(dirname "$0")/.."

files=(scripts/*.sh skills/*/scripts/*.sh tests/*.sh tests/fake-bin/gh)

for f in "${files[@]}"; do
  bash -n "$f"
done
echo "bash -n: ${#files[@]} files ok"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck が見つかりません" >&2
  exit 1
fi
# lib.sh は source される前提なので、shell を明示する
shellcheck --shell=bash "${files[@]}"
echo "shellcheck: ${#files[@]} files ok"
