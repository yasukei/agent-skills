#!/usr/bin/env bash
# Tests for skills/resolve-issue/scripts/wait_ci.sh.
# A fake gh (tests/fake-bin/gh) goes first in PATH and serves REST responses from files, so the tests do not
# depend on GitHub authentication or the network. Responses are static, so waiting cases use zero timeouts.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/resolve-issue/scripts/wait_ci.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/tests/fake-bin:$PATH"
export FAKE_REST_DIR="$WORK/rest"
SHA=abc123

reset() {
  rm -rf "$FAKE_REST_DIR"
  mkdir -p "$FAKE_REST_DIR"
  printf '{"head": {"sha": "%s"}}' "$SHA" >"$FAKE_REST_DIR/repos_o_r_pulls_1.json"
  checks '[]'
  statuses '[]'
}
checks() {
  printf '{"total_count": 0, "check_runs": %s}' "$1" >"$FAKE_REST_DIR/repos_o_r_commits_${SHA}_check-runs.json"
}
statuses() {
  # The combined status reports "pending" even when there are no statuses at all.
  printf '{"state": "pending", "total_count": 0, "statuses": %s}' "$1" >"$FAKE_REST_DIR/repos_o_r_commits_${SHA}_status.json"
}

# run_wait: run the script with zero waits; sets OUT, ERR and RC
run_wait() {
  OUT="$("$SCRIPT" 1 o/r --interval 0 --register-timeout 0 --timeout 0 2>"$WORK/err")"
  RC=$?
  ERR="$(cat "$WORK/err")"
}

run_completed=' {"name": "build", "status": "completed", "conclusion": "success", "html_url": "https://ci/build"}'

t "all check runs passed"
reset
checks "[$run_completed, {\"name\": \"lint\", \"status\": \"completed\", \"conclusion\": \"skipped\", \"html_url\": \"https://ci/lint\"}]"
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"
assert_eq "$SHA" "$(jq -r .sha <<<"$OUT")" "sha"

t "a failed check run is listed"
reset
checks "[$run_completed, {\"name\": \"test\", \"status\": \"completed\", \"conclusion\": \"failure\", \"html_url\": \"https://ci/test\"}]"
run_wait
assert_eq 1 "$RC" "exit status"
assert_eq failure "$(jq -r .state <<<"$OUT")" "state"
assert_eq '[{"name":"test","url":"https://ci/test"}]' "$(jq -c .failing <<<"$OUT")" "failing"

t "a failed commit status is listed without any check run"
reset
statuses '[{"context": "ci/external", "state": "error", "target_url": "https://ext/1"}]'
run_wait
assert_eq 1 "$RC" "exit status"
assert_eq '[{"name":"ci/external","url":"https://ext/1"}]' "$(jq -c .failing <<<"$OUT")" "failing"

t "passed check runs and statuses"
reset
checks "[$run_completed]"
statuses '[{"context": "ci/external", "state": "success", "target_url": "https://ext/1"}]'
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"

t "nothing registered: none, not success"
reset
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq none "$(jq -r .state <<<"$OUT")" "state"

t "a running check run times out"
reset
checks '[{"name": "build", "status": "in_progress", "conclusion": null, "html_url": "https://ci/build"}]'
run_wait
assert_eq 3 "$RC" "exit status"
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state"

t "a pending commit status keeps waiting although check runs are done"
reset
checks "[$run_completed]"
statuses '[{"context": "ci/external", "state": "pending", "target_url": "https://ext/1"}]'
run_wait
assert_eq 3 "$RC" "exit status"
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state"

t "an API error is not read as no CI"
reset
rm "$FAKE_REST_DIR/repos_o_r_commits_${SHA}_status.json"
run_wait
assert_eq 2 "$RC" "exit status"
assert_eq "" "$OUT" "stdout"
assert_contains "$ERR" "GitHub API request failed" "stderr"

t "a missing PR is an API error"
reset
rm "$FAKE_REST_DIR/repos_o_r_pulls_1.json"
run_wait
assert_eq 2 "$RC" "exit status"

t "invalid arguments"
reset
"$SCRIPT" 1 >/dev/null 2>&1
assert_eq 2 "$?" "missing repository"
"$SCRIPT" 1 o/r --interval x >/dev/null 2>&1
assert_eq 2 "$?" "non-numeric interval"

done_testing
