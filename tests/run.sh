#!/usr/bin/env bash
# Run all tests. CI and local runs both use this command.
#   tests/run.sh          lint and all tests
#   tests/run.sh lint     lint only (bash -n and shellcheck)
#   tests/run.sh test     tests only
set -uo pipefail

cd "$(dirname "$0")" || exit 1

what="${1:-all}"
failed=()

run() {
  echo "=== $1"
  "./$1" || failed+=("$1")
}

case "$what" in
  all | lint | test) ;;
  *) echo "usage: $0 [all|lint|test]" >&2; exit 1 ;;
esac

if [ "$what" != test ]; then
  run lint.sh
fi
if [ "$what" != lint ]; then
  for f in test_*.sh; do
    run "$f"
  done
fi

if [ "${#failed[@]}" -gt 0 ]; then
  echo "Failed: ${failed[*]}" >&2
  exit 1
fi
echo "All passed"
