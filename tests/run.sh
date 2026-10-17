#!/usr/bin/env bash
# すべてのテストを実行する。CI でもローカルでもこのコマンドを使う。
#   tests/run.sh          lint とすべてのテスト
#   tests/run.sh lint     lint（bash -n と shellcheck）だけ
#   tests/run.sh test     テストだけ
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
  echo "失敗: ${failed[*]}" >&2
  exit 1
fi
echo "すべて成功しました"
