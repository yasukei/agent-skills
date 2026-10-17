# テスト用の共通関数。各テストファイルから source する。
# 失敗したアサーションは FAILED に数え、テストファイルの最後で done_testing が終了コードにする。

FAILED=0
PASSED=0
CURRENT=""

# テストケースの開始を表示する
t() {
  CURRENT="$1"
  echo "--- $CURRENT"
}

pass() {
  PASSED=$((PASSED + 1))
}

fail() {
  FAILED=$((FAILED + 1))
  echo "FAIL [$CURRENT]: $*" >&2
}

assert_eq() {
  # assert_eq <期待値> <実際の値> <説明>
  if [ "$1" = "$2" ]; then pass; else fail "$3: 期待値 '$1'、実際 '$2'"; fi
}

assert_contains() {
  # assert_contains <文字列> <含まれるべき部分文字列> <説明>
  case "$1" in
    *"$2"*) pass ;;
    *) fail "$3: '$2' を含まない: $1" ;;
  esac
}

assert_link() {
  # assert_link <パス> <期待するリンク先>
  if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then
    pass
  else
    fail "$1 が $2 へのリンクではない"
  fi
}

assert_dir() {
  if [ -d "$1" ] && [ ! -L "$1" ]; then pass; else fail "$1 が実ディレクトリではない"; fi
}

assert_missing() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then pass; else fail "$1 が残っている"; fi
}

done_testing() {
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}
