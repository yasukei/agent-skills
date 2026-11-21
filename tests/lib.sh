# Shared test helpers, sourced by each test file.
# Failed assertions are counted in FAILED, and done_testing turns it into the exit status at the end of the test file.

FAILED=0
PASSED=0
CURRENT=""

# Print the start of a test case
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
  # assert_eq <expected> <actual> <description>
  if [ "$1" = "$2" ]; then pass; else fail "$3: expected '$1', got '$2'"; fi
}

assert_contains() {
  # assert_contains <string> <expected substring> <description>
  case "$1" in
    *"$2"*) pass ;;
    *) fail "$3: does not contain '$2': $1" ;;
  esac
}

done_testing() {
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}
