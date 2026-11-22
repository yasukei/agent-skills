#!/usr/bin/env bash
# Tests for skills/orchestrate-issue/scripts/wait_ci.sh.
# A fake gh (tests/fake-bin/gh) goes first in PATH and serves REST responses from files, so the tests do not
# depend on GitHub authentication or the network. Waiting cases use zero timeouts and interval.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/orchestrate-issue/scripts/wait_ci.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/tests/fake-bin:$PATH"
export FAKE_REST_DIR="$WORK/rest"
export FAKE_GH_LOG="$FAKE_REST_DIR/requests.log"
SHA=abc123
PR_RESPONSE="$FAKE_REST_DIR/repos_o_r_pulls_1.json"
CHECKS_RESPONSE="$FAKE_REST_DIR/repos_o_r_commits_${SHA}_check-runs.json"
RUNS_RESPONSE="$FAKE_REST_DIR/repos_o_r_actions_runs.json"
JOBS_RESPONSE="$FAKE_REST_DIR/repos_o_r_actions_runs_42_jobs.json"

reset() {
  rm -rf "$FAKE_REST_DIR"
  mkdir -p "$FAKE_REST_DIR"
  pull "$SHA" true clean >"$PR_RESPONSE"
  checks '[]'
  statuses '[]'
}
pull() {
  printf '{"head": {"sha": "%s"}, "mergeable": %s, "mergeable_state": "%s"}' "$1" "$2" "$3"
}
checks() {
  printf '{"total_count": 0, "check_runs": %s}' "$1" >"$CHECKS_RESPONSE"
}
statuses() {
  # The combined status reports "pending" even when there are no statuses at all.
  printf '{"state": "pending", "total_count": 0, "statuses": %s}' "$1" >"$FAKE_REST_DIR/repos_o_r_commits_${SHA}_status.json"
}

forbid() {
  printf '%s\n' 'gh: Resource not accessible by personal access token (HTTP 403)' >"$1.err"
}

use_actions() {
  forbid "$CHECKS_RESPONSE"
  printf '{"workflow_runs": %s}\n' "$1" >"$RUNS_RESPONSE"
}

# run_wait: run the script with zero waits; sets OUT, ERR and RC
run_wait() {
  OUT="$("$SCRIPT" 1 o/r --interval 0 --register-timeout 0 --timeout 0 "$@" 2>"$WORK/err")"
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
assert_eq true "$(jq -c .mergeable <<<"$OUT")" "mergeable"
assert_eq check-runs "$(jq -r .checks_source <<<"$OUT")" "check source"

t "a conflicting PR is reported before waiting for CI registration"
reset
pull "$SHA" false dirty >"$PR_RESPONSE"
rm "$FAKE_REST_DIR/repos_o_r_commits_${SHA}_check-runs.json"
run_wait
assert_eq 4 "$RC" "exit status"
assert_eq conflicting "$(jq -r .state <<<"$OUT")" "state"
assert_eq false "$(jq -c .mergeable <<<"$OUT")" "mergeable"
assert_eq null "$(jq -c .checks_source <<<"$OUT")" "check source before querying CI"

t "a conflict that appears during CI takes precedence over successful checks"
reset
checks "[$run_completed]"
pull "$SHA" false dirty >"$PR_RESPONSE.next"
run_wait
assert_eq 4 "$RC" "exit status"
assert_eq conflicting "$(jq -r .state <<<"$OUT")" "state"

t "a conflict interrupts a pending CI wait"
reset
checks '[{"name": "build", "status": "in_progress", "conclusion": null}]'
pull "$SHA" false dirty >"$PR_RESPONSE.next"
run_wait --timeout 5
assert_eq 4 "$RC" "exit status"
assert_eq conflicting "$(jq -r .state <<<"$OUT")" "state"

t "mergeability is retried when GitHub is computing it"
reset
pull "$SHA" null unknown >"$PR_RESPONSE"
pull "$SHA" false dirty >"$PR_RESPONSE.next"
run_wait --mergeability-only
assert_eq 4 "$RC" "exit status"
assert_eq conflicting "$(jq -r .state <<<"$OUT")" "state"

t "mergeability-only skips CI and does not flag behind or blocked as conflicts"
reset
rm "$FAKE_REST_DIR/repos_o_r_commits_${SHA}_check-runs.json"
for merge_state in behind blocked; do
  pull "$SHA" true "$merge_state" >"$PR_RESPONSE"
  run_wait --mergeability-only
  assert_eq 0 "$RC" "$merge_state exit status"
  assert_eq no_conflict "$(jq -r .state <<<"$OUT")" "$merge_state state"
  assert_eq null "$(jq -c .checks_source <<<"$OUT")" "$merge_state check source"
done

t "unknown mergeability after retries stops the workflow"
reset
checks "[$run_completed]"
pull "$SHA" null unknown >"$PR_RESPONSE"
run_wait
assert_eq 3 "$RC" "exit status"
assert_eq mergeability_timeout "$(jq -r .state <<<"$OUT")" "state"
assert_eq null "$(jq -c .mergeable <<<"$OUT")" "mergeable"

t "a new head cannot be paired with the previous head's CI"
reset
checks "[$run_completed]"
pull def456 true clean >"$PR_RESPONSE.next"
run_wait
assert_eq 2 "$RC" "exit status"
assert_eq "" "$OUT" "stdout"
assert_contains "$ERR" "head changed while waiting" "stderr"

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
rm "$PR_RESPONSE"
run_wait
assert_eq 2 "$RC" "exit status"

t "a malformed PR response is an API error"
reset
printf '{' >"$PR_RESPONSE"
run_wait
assert_eq 2 "$RC" "exit status"
assert_eq "" "$OUT" "stdout"
assert_contains "$ERR" "GitHub API request failed" "stderr"

t "an old failure from a re-run check suite is dropped"
reset
checks '[
  {"name": "test", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "old", "check_suite": {"id": 1}},
  {"name": "test", "status": "completed", "conclusion": "success", "started_at": "2026-01-01T02:00:00Z", "html_url": "new", "check_suite": {"id": 2}}]'
printf '%s' '{"workflow_runs": [{"check_suite_id": 1, "name": "CI", "event": "pull_request"}, {"check_suite_id": 2, "name": "CI", "event": "pull_request"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs.json"
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"

t "a newer re-run still running keeps waiting"
reset
checks '[
  {"name": "test", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "old", "check_suite": {"id": 1}},
  {"name": "test", "status": "in_progress", "conclusion": null, "started_at": "2026-01-01T02:00:00Z", "html_url": "new", "check_suite": {"id": 2}}]'
printf '%s' '{"workflow_runs": [{"check_suite_id": 1, "name": "CI", "event": "pull_request"}, {"check_suite_id": 2, "name": "CI", "event": "pull_request"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs.json"
run_wait
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state"

t "same-named checks in different workflows or events stay separate"
reset
checks '[
  {"name": "lint", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "push", "check_suite": {"id": 3}},
  {"name": "lint", "status": "completed", "conclusion": "success", "started_at": "2026-01-01T02:00:00Z", "html_url": "pr", "check_suite": {"id": 4}}]'
printf '%s' '{"workflow_runs": [{"check_suite_id": 3, "name": "Lint", "event": "push"}, {"check_suite_id": 4, "name": "Lint", "event": "pull_request"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs.json"
run_wait
assert_eq failure "$(jq -r .state <<<"$OUT")" "state"
assert_eq '[{"name":"lint","url":"push"}]' "$(jq -c .failing <<<"$OUT")" "failing"

t "check suites with unknown workflow runs stay separate"
reset
checks '[
  {"name": "test", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "a", "check_suite": {"id": 5}},
  {"name": "test", "status": "completed", "conclusion": "success", "started_at": "2026-01-01T02:00:00Z", "html_url": "b", "check_suite": {"id": 6}}]'
run_wait
assert_eq failure "$(jq -r .state <<<"$OUT")" "state"
assert_eq '[{"name":"test","url":"a"}]' "$(jq -c .failing <<<"$OUT")" "failing"

action_run='{"id": 42, "name": "CI", "event": "pull_request"}'
action_pending='{"name": "build", "status": "queued", "conclusion": null}'
action_failed='{"name": "build", "status": "completed", "conclusion": "failure", "html_url": "https://ci/failed"}'

t "Actions fallback waits through a queued job and reports success"
reset
use_actions "[$action_run]"
printf '{"jobs": [%s]}\n' "$action_pending" >"$JOBS_RESPONSE"
printf '{"jobs": [%s]}\n' "$run_completed" >"$JOBS_RESPONSE.next"
run_wait --timeout 5
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"
assert_eq actions "$(jq -r .checks_source <<<"$OUT")" "check source"
assert_contains "$(cat "$FAKE_GH_LOG")" "actions/runs?head_sha=$SHA" "reads runs for the head SHA"
assert_eq 2 "$(grep -c 'actions/runs/42/jobs' "$FAKE_GH_LOG")" "polled jobs twice"

t "Actions fallback reports failed jobs and commit statuses"
reset
use_actions "[$action_run]"
printf '{"jobs": [%s]}\n' "$action_failed" >"$JOBS_RESPONSE"
statuses '[{"context": "ci/external", "state": "failure", "target_url": "https://ext/1"}]'
run_wait
assert_eq 1 "$RC" "exit status"
assert_eq failure "$(jq -r .state <<<"$OUT")" "state"
assert_eq actions "$(jq -r .checks_source <<<"$OUT")" "check source"
assert_eq '[{"name":"build","url":"https://ci/failed"},{"name":"ci/external","url":"https://ext/1"}]' \
  "$(jq -c .failing <<<"$OUT")" "failing"

t "Actions fallback reports a timeout while a job is queued"
reset
use_actions "[$action_run]"
printf '{"jobs": [%s]}\n' "$action_pending" >"$JOBS_RESPONSE"
run_wait
assert_eq 3 "$RC" "exit status"
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state"
assert_eq actions "$(jq -r .checks_source <<<"$OUT")" "check source"

t "a queued workflow is pending even before jobs register"
reset
use_actions '[{"id": 42, "name": "CI", "event": "pull_request", "status": "queued"}]'
printf '{"jobs": []}\n' >"$JOBS_RESPONSE"
run_wait
assert_eq 3 "$RC" "exit status before any checks register"
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state before any checks register"
statuses '[{"context": "ci/external", "state": "success"}]'
run_wait
assert_eq 3 "$RC" "exit status with a passed status"
assert_eq timeout "$(jq -r .state <<<"$OUT")" "state with a passed status"

t "Actions fallback handles a full page of jobs with step details"
reset
use_actions "[$action_run]"
jq -n '
  {jobs: [range(100) |
    {name: "build-\(.)", status: "completed", conclusion: "success", html_url: "https://ci/build-\(.)",
     steps: [range(12) | {name: "Run build step \(.)", status: "completed", conclusion: "success",
                         started_at: "2026-01-01T01:00:00Z", completed_at: "2026-01-01T01:01:00Z"}]}]}' \
  >"$JOBS_RESPONSE"
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"

t "Actions fallback reads only the latest attempt of a re-run"
reset
use_actions '[{"id": 42, "name": "CI", "event": "pull_request", "run_attempt": 2}]'
printf '{"jobs": [%s]}\n' "$run_completed" >"$JOBS_RESPONSE"
printf '{"jobs": [%s]}\n' "$action_failed" >"$FAKE_REST_DIR/repos_o_r_actions_runs_42_attempts_1_jobs.json"
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq success "$(jq -r .state <<<"$OUT")" "state"
assert_contains "$(cat "$FAKE_GH_LOG")" "actions/runs/42/jobs?filter=latest" "requests the latest attempt"

t "Actions jobs deduplicate across runs but stay separate across workflows or events"
reset
use_actions "[$action_run, {\"id\": 43, \"name\": \"CI\", \"event\": \"pull_request\"}]"
printf '%s\n' '{"workflow_runs": [{"id": 44, "name": "CI", "event": "push"}, {"id": 45, "name": "Other", "event": "pull_request"}]}' \
  >>"$RUNS_RESPONSE"
printf '%s\n' '{"jobs": [{"name": "build", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "old"}]}' \
  >"$JOBS_RESPONSE"
printf '%s\n' '{"jobs": [{"name": "build", "status": "completed", "conclusion": "success", "started_at": "2026-01-01T02:00:00Z"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs_43_jobs.json"
printf '%s\n' '{"jobs": [{"name": "build", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "push"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs_44_jobs.json"
printf '%s\n' '{"jobs": []}' \
  '{"jobs": [{"name": "build", "status": "completed", "conclusion": "failure", "started_at": "2026-01-01T01:00:00Z", "html_url": "other"}]}' \
  >"$FAKE_REST_DIR/repos_o_r_actions_runs_45_jobs.json"
run_wait
assert_eq 1 "$RC" "exit status"
assert_eq '[{"name":"build","url":"push"},{"name":"build","url":"other"}]' "$(jq -c .failing <<<"$OUT")" "failing"

t "Actions fallback reports none when no workflow runs register"
reset
use_actions '[]'
run_wait
assert_eq 0 "$RC" "exit status"
assert_eq none "$(jq -r .state <<<"$OUT")" "state"
assert_eq actions "$(jq -r .checks_source <<<"$OUT")" "check source"

t "a 403 from either Actions endpoint is an API error"
for endpoint in "$RUNS_RESPONSE" "$JOBS_RESPONSE"; do
  reset
  use_actions "[$action_run]"
  forbid "$endpoint"
  run_wait
  assert_eq 2 "$RC" "exit status"
  assert_eq "" "$OUT" "stdout"
  assert_contains "$ERR" "GitHub API request failed" "stderr"
done

t "a check-runs error other than 403 does not use the Actions fallback"
reset
rm "$CHECKS_RESPONSE"
printf '{"workflow_runs": []}\n' >"$RUNS_RESPONSE"
run_wait
assert_eq 2 "$RC" "exit status"
assert_eq "" "$OUT" "stdout"
assert_contains "$ERR" "HTTP 404" "stderr"

t "invalid arguments"
reset
"$SCRIPT" 1 >/dev/null 2>&1
assert_eq 2 "$?" "missing repository"
run_wait --interval x
assert_eq 2 "$RC" "non-numeric interval"
assert_eq "usage:" "${ERR%% *}" "validate the interval before comparing it"

done_testing
