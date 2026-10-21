#!/usr/bin/env bash
# Tests for skills/issue-to-pr/scripts/pr_status.sh.
# A fake gh (tests/fake-bin/gh) goes first in PATH, so the tests do not depend on GitHub authentication or the network.
# Each case runs on both the GraphQL path and the REST / CCR route path used where GraphQL returns 403,
# and checks that both give the same result (run_status).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/issue-to-pr/scripts/pr_status.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/tests/fake-bin:$PATH"
export FAKE_GRAPHQL="$WORK/graphql.json"
export FAKE_GH_LOG="$WORK/gh.log"
export FAKE_REST_DIR="$WORK/rest"
mkdir -p "$FAKE_REST_DIR"

# gh api graphql error where GraphQL is not available (Claude Code on the web)
GRAPHQL_403='gh: GitHub GraphQL is not available from Claude Code sessions; use the REST API (gh api repos/{owner}/{repo}/...). (HTTP 403)'
# PR head SHA used on the REST path
SHA=abc123

# Path of the file the fake gh api <path> returns
rest_file() {
  printf '%s/%s.json' "$FAKE_REST_DIR" "$(printf '%s' "$1" | tr / _)"
}

# Build REST / CCR route responses with the same content from the GraphQL response ($FAKE_GRAPHQL)
write_rest_from_graphql() {
  local pr
  pr="$(jq '.data.repository.pullRequest' "$FAKE_GRAPHQL")"
  jq --arg sha "$SHA" '{
    html_url: .url,
    state: (if .state == "OPEN" then "open" else "closed" end),
    merged: (.state == "MERGED"),
    draft: .isDraft,
    mergeable: (if .mergeable == "MERGEABLE" then true elif .mergeable == "CONFLICTING" then false else null end),
    user: { login: .author.login, type: "User" },
    head: { ref: .headRefName, sha: $sha },
    base: { ref: .baseRefName }
  }' <<<"$pr" >"$(rest_file repos/o/r/pulls/1)"
  local user='{ login: .author.login, type: (if .author.__typename == "Bot" then "Bot" else "User" end) }'
  jq "[ .reviews.nodes[] | { user: $user, state, submitted_at: .submittedAt, body } ]" <<<"$pr" \
    >"$(rest_file repos/o/r/pulls/1/reviews)"
  jq "[ .reviewThreads.nodes[].comments.nodes[] | { id: .databaseId, user: $user, body, created_at: .createdAt, html_url: .url } ]" \
    <<<"$pr" >"$(rest_file repos/o/r/pulls/1/comments)"
  jq "[ .comments.nodes[] | { id: .databaseId, user: $user, body, created_at: .createdAt, html_url: .url } ]" <<<"$pr" \
    >"$(rest_file repos/o/r/issues/1/comments)"
  jq '[ .reviewThreads.nodes[] | { resolved: .isResolved, outdated: .isOutdated, path, line,
        comment_ids: [ .comments.nodes[].databaseId ] } ]' <<<"$pr" \
    >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
}

# Build the output of gh api graphql.
#   write_pr <state> <mergeable> <reviews> <reviewThreads> <comments>
# The last three are JSON arrays of nodes. The PR author is "me"
write_pr() {
  jq -n --arg state "$1" --arg mergeable "$2" --arg sha "$SHA" \
    --argjson reviews "$3" --argjson threads "$4" --argjson comments "$5" '{
    data: { repository: { pullRequest: {
      url: "https://github.com/o/r/pull/1",
      state: $state, isDraft: false, mergeable: $mergeable, reviewDecision: null,
      author: { login: "me" }, headRefName: "feat/1-x", headRefOid: $sha, baseRefName: "main",
      reviews: { nodes: $reviews },
      reviewThreads: { nodes: $threads },
      comments: { nodes: $comments }
    } } }
  }' >"$FAKE_GRAPHQL"
  write_rest_from_graphql
}

# Build one review thread: <isResolved> <author> <first comment body> [<author> <body>]...
thread() {
  local resolved="$1"
  shift
  local comments='[]' i=1
  while [ $# -ge 2 ]; do
    comments="$(jq -c --arg a "$1" --arg b "$2" --argjson i "$i" \
      '. + [{ databaseId: $i, author: { login: $a, __typename: "User" }, body: $b, createdAt: "2026-01-01T00:00:00Z", url: "u\($i)" }]' \
      <<<"$comments")"
    i=$((i + 1))
    shift 2
  done
  jq -nc --argjson r "$resolved" --argjson c "$comments" \
    '{ id: "T1", isResolved: $r, isOutdated: false, path: "a.sh", line: 1, comments: { nodes: $c } }'
}

# Build one review: <author> <state> <body> [<date>]
review() {
  jq -nc --arg a "$1" --arg s "$2" --arg b "$3" --arg at "${4:-2026-01-01T00:00:00Z}" \
    '{ author: { login: $a, __typename: "User" }, state: $s, submittedAt: $at, body: $b }'
}

# Build one PR comment: <author> <body> [<date>]
comment() {
  jq -nc --arg a "$1" --arg b "$2" --arg at "${3:-2026-01-01T00:00:00Z}" \
    '{ databaseId: 100, author: { login: $a, __typename: "User" }, body: $b, createdAt: $at, url: "c" }'
}

# Turn the review or comment on stdin into a bot's post
as_bot() {
  jq -c '.author.__typename = "Bot"'
}

# For the older tests: one unresolved thread (the first comment is the reviewer's; the second body is the argument)
write_graphql() {
  write_pr OPEN MERGEABLE '[]' "[$(thread false me "[P2] Please fix this" me "$1")]" '[]'
}

# Run pr_status.sh once and store the results in OUT, ERR and RC
run_once() {
  RC=0
  "$SCRIPT" 1 o/r >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# Run pr_status.sh where GraphQL returns 403 (the REST / CCR route path)
run_rest() {
  FAKE_GRAPHQL_RC=1 FAKE_GRAPHQL_ERR="$GRAPHQL_403" run_once
}

# Run pr_status.sh on both the GraphQL path and the REST path, and check that the results match.
# OUT, ERR and RC hold the results of the GraphQL path.
# Thread IDs are not available on the REST path (null), so they are not compared
run_status() {
  local rc out err
  run_rest
  rc="$RC" out="$OUT"
  run_once
  err="$ERR"
  assert_eq "$RC" "$rc" "same exit status on the REST path"
  if [ -z "$OUT" ] || [ -z "$out" ]; then
    assert_eq "$OUT" "$out" "same stdout on the REST path"
  elif jq -e -n --argjson g "$OUT" --argjson r "$out" \
    '($g | del(.threads[].id)) == ($r | del(.threads[].id))' >/dev/null; then
    pass
  else
    fail "REST path output differs from the GraphQL path: $(diff <(jq -S 'del(.threads[].id)' <<<"$OUT") <(jq -S 'del(.threads[].id)' <<<"$out"))"
  fi
  ERR="$err"
}

# Set the result of the fake gh pr checks: <stdout> <stderr> <exit status>
# Also build matching check runs for the REST path. When gh pr checks errors, the check runs cannot be fetched either
checks() {
  export FAKE_CHECKS_OUT="$1" FAKE_CHECKS_ERR="$2" FAKE_CHECKS_RC="$3"
  local runs
  if [ -n "$1" ]; then
    runs="$(jq -c '[ .[] | {
      name,
      status: (if .bucket == "pending" then "in_progress" else "completed" end),
      conclusion: ({ pass: "success", fail: "failure", cancel: "cancelled", skipping: "skipped" }[.bucket]),
      details_url: .link,
      check_suite: { id: 1 }
    } ]' <<<"$1")"
  elif [[ "$2" == *"no checks reported"* ]]; then
    runs='[]'
  else
    rm -f "$(rest_file "repos/o/r/commits/$SHA/check-runs")"
    return
  fi
  jq -n --argjson r "$runs" '{ total_count: ($r | length), check_runs: $r }' \
    >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
  echo '{ "state": "pending", "statuses": [] }' >"$(rest_file "repos/o/r/commits/$SHA/status")"
  echo '{ "workflow_runs": [{ "check_suite_id": 1, "name": "CI", "event": "pull_request" }] }' \
    >"$(rest_file repos/o/r/actions/runs)"
}

field() {
  jq -r "$1" <<<"$OUT"
}

PASS_CHECK='{"name":"test","state":"SUCCESS","bucket":"pass","link":"l1","workflow":"CI"}'
FAIL_CHECK='{"name":"lint","state":"FAILURE","bucket":"fail","link":"l2","workflow":"CI"}'
PENDING_CHECK='{"name":"build","state":"IN_PROGRESS","bucket":"pending","link":"l3","workflow":"CI"}'

write_graphql "Added a null check (abc1234)

<!-- issue-to-pr -->"

# ---------------------------------------------------------------------------
t "CI passing"
checks "[$PASS_CHECK]" "" 0
run_status
assert_eq 0 "$RC" "exit status"
assert_eq passing "$(field .ci.summary)" "ci.summary"
assert_eq 0 "$(field '.ci.failing | length')" "ci.failing"
assert_contains "$(cat "$FAKE_GH_LOG")" "pr checks 1 --repo o/r --json" "passes the PR number and repository to gh pr checks"
assert_contains "$(cat "$FAKE_GH_LOG")" "-F owner=o -F name=r -F pr=1" "passes owner, name and PR number to GraphQL"
assert_contains "$(cat "$FAKE_GH_LOG")" "repos/o/r/pulls/1/ccr/review_threads" "REST path fetches threads through the CCR route"
assert_contains "$(cat "$FAKE_GH_LOG")" "repos/o/r/commits/$SHA/check-runs" "REST path fetches the check runs of the head SHA"

# ---------------------------------------------------------------------------
t "CI failing"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
run_status
assert_eq 0 "$RC" "exit status"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq lint "$(field '.ci.failing | map(.name) | join(",")')" "ci.failing"

# ---------------------------------------------------------------------------
t "CI pending"
checks "[$PASS_CHECK,$PENDING_CHECK]" "" 8
run_status
assert_eq 0 "$RC" "exit status"
assert_eq pending "$(field .ci.summary)" "ci.summary"
assert_eq build "$(field '.ci.pending | join(",")')" "ci.pending"

# ---------------------------------------------------------------------------
t "no checks"
checks "" "no checks reported on the 'feat/1-x' branch" 1
run_status
assert_eq 0 "$RC" "exit status"
assert_eq none "$(field .ci.summary)" "ci.summary"

# ---------------------------------------------------------------------------
t "other gh pr checks errors"
checks "" "HTTP 401: Bad credentials" 1
run_status
assert_eq 1 "$RC" "exit status"
assert_eq "" "$OUT" "prints no result to stdout"
assert_contains "$ERR" "HTTP 401: Bad credentials" "prints the error to stderr"

# ---------------------------------------------------------------------------
t "marker detection"
checks "[$PASS_CHECK]" "" 0
write_graphql "Added a null check (abc1234)

<!-- issue-to-pr -->"
run_status
assert_eq true "$(field '.threads[0].lastCommentByMe')" "with marker"
write_graphql "Still not fixed"
run_status
assert_eq 0 "$RC" "exit status"
assert_eq false "$(field '.threads[0].lastCommentByMe')" "without marker"

# ---------------------------------------------------------------------------
# Exit decision (verdict)

MINE='<!-- issue-to-pr -->'
BY_REVIEWER='<!-- pr-review -->'
COMPLETE='<!-- review-complete -->'

# assert_verdict <status> <done> <description>
assert_verdict() {
  assert_eq 0 "$RC" "$3: exit status"
  assert_eq "$1" "$(field .verdict.status)" "$3: verdict.status"
  assert_eq "$2" "$(field .verdict.done)" "$3: verdict.done"
}

checks "[$PASS_CHECK]" "" 0

t "CI passing with zero reviews and zero threads is waiting for review"
write_pr OPEN MERGEABLE '[]' '[]' '[]'
run_status
assert_verdict waiting_for_review false "no review"
assert_eq false "$(field .review.activity)" "review.activity"
assert_eq none "$(field .review.mode)" "review.mode"

t "own marked replies alone do not count as reviewed"
# Replying to a thread creates a COMMENTED review with an empty body under the author's name
write_pr OPEN MERGEABLE "[$(review me COMMENTED "")]" '[]' \
  "[$(comment me "Opened the PR.

$MINE")]"
run_status
assert_verdict waiting_for_review false "own replies only"

t "a completion marker in own post does not complete"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment me "Review complete $COMPLETE

$MINE")]"
run_status
assert_verdict waiting_for_review false "completion marker in own post"

t "same account: an intermediate question (unresolved thread) does not complete"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "I have a question.

$BY_REVIEWER")]" \
  "[$(thread false me "[Question] Is this intended?

$BY_REVIEWER")]" '[]'
run_status
assert_verdict review_in_progress false "unresolved question thread"
assert_eq same_account "$(field .review.mode)" "review.mode"
assert_eq 1 "$(field .review.unresolvedReviewerThreadCount)" "unresolved thread count"

t "same account: an intermediate question in a PR comment does not complete"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment me "Where is this function called from?")]"
run_status
assert_verdict review_in_progress false "question in PR comment"
assert_eq false "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "same account: an explicit review complete with no findings can finish"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "No findings.

$COMPLETE
$BY_REVIEWER")]" '[]' '[]'
run_status
assert_verdict ready true "review with completion marker"
assert_eq true "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "same account: explicit completion does not finish while CI is running"
checks "[$PASS_CHECK,$PENDING_CHECK]" "" 8
run_status
assert_verdict ci_pending false "CI running"
checks "[$PASS_CHECK]" "" 0

t "same account: can finish when all finding threads are resolved"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "## Review result

$BY_REVIEWER")]" \
  "[$(thread true me "[P2] Please fix this

$BY_REVIEWER" me "Fixed (abc1234)

$MINE")]" '[]'
run_status
assert_verdict ready true "all threads resolved"

t "same account: does not finish with an unresolved finding thread"
write_pr OPEN MERGEABLE '[]' \
  "[$(thread false me "[P2] Please fix this

$BY_REVIEWER" me "Fixed (abc1234)

$MINE")]" '[]'
run_status
assert_verdict review_in_progress false "unresolved thread"

t "same account: does not finish with an unresolved thread even with a completion marker"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "$COMPLETE")]" \
  "[$(thread false me "[P1] Raised again")]" '[]'
run_status
assert_verdict review_in_progress false "completion marker and unresolved thread"

t "other account: does not finish while waiting for Approve"
write_pr OPEN MERGEABLE "[$(review alice COMMENTED "## Review result")]" \
  "[$(thread true alice "[P3] Optional")]" '[]'
run_status
assert_verdict review_in_progress false "COMMENTED only"
assert_eq other_account "$(field .review.mode)" "review.mode"
write_pr OPEN MERGEABLE "[$(review alice CHANGES_REQUESTED "Please fix this")]" '[]' '[]'
run_status
assert_verdict review_in_progress false "changes requested"

t "other account: can finish when the latest review is Approve"
write_pr OPEN MERGEABLE "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict ready true "Approve"

t "other account: does not finish while CI fails even with Approve"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
run_status
assert_verdict ci_failing false "CI failing"
checks "[$PASS_CHECK]" "" 0

t "same account: a question after the completion marker does not complete"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "No findings.

$COMPLETE
$BY_REVIEWER" 2026-01-01T00:00:00Z)]" '[]' \
  "[$(comment me "One more thing: what does this variable name mean?" 2026-01-01T01:00:00Z)]"
run_status
assert_verdict review_in_progress false "question after completion marker"
assert_eq false "$(field .review.explicitCompletion)" "review.explicitCompletion"

t "bot posts alone keep waiting for review"
write_pr OPEN MERGEABLE "[$(review copilot-pull-request-reviewer COMMENTED "Overview" | as_bot)]" '[]' \
  "[$(comment codecov "Coverage: 90%" | as_bot)]"
run_status
assert_verdict waiting_for_review false "bot only"
assert_eq false "$(field .hasOtherReviewer)" "a bot does not count as another account's reviewer"

t "same account: a completion marker finishes even with a bot review"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "No findings.

$COMPLETE
$BY_REVIEWER"),$(review copilot-pull-request-reviewer COMMENTED "Overview" 2026-01-01T02:00:00Z | as_bot)]" '[]' '[]'
run_status
assert_verdict ready true "bot review and completion marker"

t "other account: a completion marker in a PR comment alone does not finish"
write_pr OPEN MERGEABLE '[]' '[]' "[$(comment alice "LGTM $COMPLETE")]"
run_status
assert_verdict review_in_progress false "completion marker from another account"
assert_eq other_account "$(field .review.mode)" "review.mode"

t "other account: can finish with Approve even with unresolved threads (Approve is the reviewer's call)"
write_pr OPEN MERGEABLE "[$(review alice APPROVED "LGTM")]" "[$(thread false alice "[P3] Optional")]" '[]'
run_status
assert_verdict ready true "Approve and unresolved thread"

t "does not finish while mergeable is not computed yet"
write_pr OPEN UNKNOWN "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict mergeable_unknown false "mergeable UNKNOWN"

t "does not finish while conflicting"
write_pr OPEN CONFLICTING "[$(review alice APPROVED "LGTM")]" '[]' '[]'
run_status
assert_verdict conflicting false "conflict"

t "finishes when merged or closed"
checks "[$PASS_CHECK,$FAIL_CHECK]" "" 1
write_pr MERGED UNKNOWN '[]' '[]' '[]'
run_status
assert_verdict merged true "merged"
write_pr CLOSED UNKNOWN '[]' '[]' '[]'
run_status
assert_verdict closed true "closed"

# ---------------------------------------------------------------------------
# Cases specific to the REST / CCR route path

checks "[$PASS_CHECK]" "" 0
write_pr OPEN MERGEABLE '[]' '[]' '[]'

t "REST: does not call gh pr checks when GraphQL returns 403"
: >"$FAKE_GH_LOG"
run_rest
assert_verdict waiting_for_review false "REST path"
assert_contains "$(cat "$FAKE_GH_LOG")" "api graphql" "tries GraphQL first"
if grep -q "^pr checks" "$FAKE_GH_LOG"; then fail "calls gh pr checks"; else pass; fi

t "REST: does not switch to REST on GraphQL errors other than 403"
: >"$FAKE_GH_LOG"
FAKE_GRAPHQL_RC=1 FAKE_GRAPHQL_ERR="HTTP 502: Bad Gateway" run_once
assert_eq 1 "$RC" "exit status"
assert_eq "" "$OUT" "prints no result to stdout"
assert_contains "$ERR" "HTTP 502: Bad Gateway" "prints the error to stderr"
if grep -q "ccr/review_threads" "$FAKE_GH_LOG"; then fail "switches to REST"; else pass; fi

t "REST: fails when threads cannot be fetched through the CCR route"
rm "$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_eq 1 "$RC" "exit status"
assert_eq "" "$OUT" "prints no result to stdout"
assert_contains "$ERR" "HTTP 404" "prints the error to stderr"
assert_contains "$ERR" "GraphQL is not available" "also prints the GraphQL error from before the switch"
write_pr OPEN MERGEABLE '[]' '[]' '[]'

t "REST: state and bucket of check runs and commit statuses"
jq -n '{ check_runs: [
  { name: "ok",       status: "completed",   conclusion: "success",         details_url: "d1", check_suite: { id: 1 } },
  { name: "skip",     status: "completed",   conclusion: "skipped",         details_url: "d2", check_suite: { id: 1 } },
  { name: "neutral",  status: "completed",   conclusion: "neutral",         details_url: "d3", check_suite: { id: 2 } },
  { name: "timeout",  status: "completed",   conclusion: "timed_out",       details_url: "d4", check_suite: { id: 1 } },
  { name: "action",   status: "completed",   conclusion: "action_required", details_url: "d5", check_suite: { id: 1 } },
  { name: "cancel",   status: "completed",   conclusion: "cancelled",       details_url: "d6", check_suite: { id: 1 } },
  { name: "queued",   status: "queued",      conclusion: null,              details_url: "d7", check_suite: { id: 1 } },
  { name: "running",  status: "in_progress", conclusion: null,              html_url: "h8",    check_suite: { id: 1 } }
] }' >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
jq -n '{ state: "failure", statuses: [
  { context: "ci/ext-ok",   state: "success", target_url: "s1" },
  { context: "ci/ext-err",  state: "error",   target_url: "s2" },
  { context: "ci/ext-fail", state: "failure", target_url: null },
  { context: "ci/ext-wait", state: "pending", target_url: "s4" }
] }' >"$(rest_file "repos/o/r/commits/$SHA/status")"
run_rest
assert_eq 0 "$RC" "exit status"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq "timeout,action,cancel,ci/ext-err,ci/ext-fail" "$(field '.ci.failing | map(.name) | join(",")')" "ci.failing"
assert_eq "queued,running,ci/ext-wait" "$(field '.ci.pending | join(",")')" "ci.pending"
assert_eq "TIMED_OUT fail d4 CI" "$(field '.ci.failing[0] | "\(.state) \(.bucket) \(.link) \(.workflow)"')" "check run conversion"
assert_eq "ERROR fail s2 " "$(field '.ci.failing[3] | "\(.state) \(.bucket) \(.link) \(.workflow)"')" "commit status conversion"
assert_eq "" "$(field '.ci.failing[4].link')" "empty string when target_url is null"
checks "[$PASS_CHECK]" "" 0

t "REST: continues with an empty workflow name when workflow runs cannot be fetched"
checks "[$FAIL_CHECK]" "" 1
rm "$(rest_file repos/o/r/actions/runs)"
run_rest
assert_eq 0 "$RC" "exit status"
assert_eq failing "$(field .ci.summary)" "ci.summary"
assert_eq "" "$(field '.ci.failing[0].workflow')" "workflow name"
checks "[$PASS_CHECK]" "" 0

t "REST: builds multiple threads in comment_ids order"
write_pr OPEN MERGEABLE '[]' '[]' '[]'
jq -n --arg mine "$MINE" '[
  { id: 11, user: { login: "me", type: "User" }, body: "[P1] First", created_at: "2026-01-01T00:00:00Z", html_url: "u11" },
  { id: 21, user: { login: "me", type: "User" }, body: "[P2] Second", created_at: "2026-01-01T00:01:00Z", html_url: "u21" },
  { id: 12, user: { login: "me", type: "User" }, body: ("Fixed\n\n" + $mine), created_at: "2026-01-01T00:02:00Z", html_url: "u12" },
  { id: 22, user: { login: "me", type: "User" }, body: "Not yet", created_at: "2026-01-01T00:03:00Z", html_url: "u22" }
]' >"$(rest_file repos/o/r/pulls/1/comments)"
echo '[
  { "resolved": true,  "outdated": true,  "path": "a.sh", "line": null, "comment_ids": [11, 12] },
  { "resolved": false, "outdated": false, "path": "b.sh", "line": 3,    "comment_ids": [21, 22] }
]' >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_verdict review_in_progress false "unresolved threads"
assert_eq "11,12|21,22" "$(field '.threads | map(.comments | map(.databaseId) | join(",")) | join("|")')" "comments per thread"
assert_eq "11,21" "$(field '.threads | map(.rootCommentId) | join(",")')" "rootCommentId"
assert_eq "true,false" "$(field '.threads | map(.lastCommentByMe) | join(",")')" "lastCommentByMe"
assert_eq "true b.sh 3" "$(field '.threads[0].isOutdated, .threads[1].path, .threads[1].line' | paste -sd' ')" "isOutdated, path and line"
assert_eq 1 "$(field .unresolvedThreadCount)" "unresolvedThreadCount"
assert_eq 2 "$(field .review.reviewerThreadCount)" "review.reviewerThreadCount"
assert_eq null "$(field '.threads[0].id')" "thread ID is not available through REST"
assert_eq null "$(field .reviewDecision)" "reviewDecision is not available through REST"

t "REST: drops threads whose comments are all missing from the review comment list"
echo '[
  { "resolved": false, "outdated": false, "path": "c.sh", "line": 1, "comment_ids": [99] },
  { "resolved": false, "outdated": false, "path": "b.sh", "line": 3, "comment_ids": [21, 99, 22] }
]' >"$(rest_file repos/o/r/pulls/1/ccr/review_threads)"
run_rest
assert_verdict review_in_progress false "comments missing from the list"
assert_eq "21,22" "$(field '.threads | map(.comments | map(.databaseId) | join(",")) | join("|")')" "drops comments and threads missing from the list"

t "REST: drops results from an old re-run check suite"
write_pr OPEN MERGEABLE "[$(review me COMMENTED "No findings.

$COMPLETE
$BY_REVIEWER")]" '[]' '[]'
jq -n '{ check_runs: [
  { name: "test", status: "completed", conclusion: "cancelled", started_at: "2026-01-01T01:00:00Z", details_url: "old", check_suite: { id: 1 } },
  { name: "test", status: "completed", conclusion: "success",   started_at: "2026-01-01T02:00:00Z", details_url: "new", check_suite: { id: 2 } }
] }' >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
jq -n '{ workflow_runs: [
  { check_suite_id: 1, name: "CI", event: "pull_request" },
  { check_suite_id: 2, name: "CI", event: "pull_request" },
  { check_suite_id: 3, name: "Lint", event: "push" },
  { check_suite_id: 4, name: "Lint", event: "pull_request" }
] }' >"$(rest_file repos/o/r/actions/runs)"
run_rest
assert_verdict ready true "old cancellation and newer success"
assert_eq passing "$(field .ci.summary)" "ci.summary"
# A different event keeps a separate check (same as gh pr checks)
jq -n '{ check_runs: [
  { name: "lint", status: "completed", conclusion: "failure", started_at: "2026-01-01T03:00:00Z", details_url: "l1", check_suite: { id: 3 } },
  { name: "lint", status: "completed", conclusion: "success", started_at: "2026-01-01T02:00:00Z", details_url: "l2", check_suite: { id: 4 } },
  { name: "test", status: "completed", conclusion: "success", started_at: "2026-01-01T02:00:00Z", details_url: "new", check_suite: { id: 2 } }
] }' >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
run_rest
assert_verdict ci_failing false "push failure"
assert_eq "lint l1 Lint" "$(field '.ci.failing | map("\(.name) \(.link) \(.workflow)") | join(",")')" "ci.failing"

t "REST: same-named checks from a check suite with unknown workflow run stay separate checks"
# The test in CI is cancelled; the test in another workflow, Lint, is a newer success
jq -n '{ check_runs: [
  { name: "test", status: "completed", conclusion: "cancelled", started_at: "2026-01-01T01:00:00Z", details_url: "ci",   check_suite: { id: 1 } },
  { name: "test", status: "completed", conclusion: "success",   started_at: "2026-01-01T02:00:00Z", details_url: "lint", check_suite: { id: 3 } }
] }' >"$(rest_file "repos/o/r/commits/$SHA/check-runs")"
# When workflow runs cannot be fetched
rm "$(rest_file repos/o/r/actions/runs)"
run_rest
assert_verdict ci_failing false "workflow runs cannot be fetched"
assert_eq "test ci" "$(field '.ci.failing | map("\(.name) \(.link)") | join(",")')" "ci.failing"
# When the list has no matching check suite
echo '{ "workflow_runs": [{ "check_suite_id": 3, "name": "Lint", "event": "pull_request" }] }' \
  >"$(rest_file repos/o/r/actions/runs)"
run_rest
assert_verdict ci_failing false "no check suite in the list"
assert_eq "test ci" "$(field '.ci.failing | map("\(.name) \(.link)") | join(",")')" "ci.failing"

t "an old gh whose gh pr checks has no --json gets CI through REST"
checks "[$PASS_CHECK]" "" 0
export FAKE_CHECKS_OUT="" FAKE_CHECKS_ERR="unknown flag: --json

Usage:  gh pr checks [<number> | <url> | <branch>] [flags]" FAKE_CHECKS_RC=1
: >"$FAKE_GH_LOG"
run_once
assert_verdict ready true "old gh"
assert_eq passing "$(field .ci.summary)" "ci.summary"
assert_contains "$(cat "$FAKE_GH_LOG")" "repos/o/r/commits/$SHA/check-runs" "fetches the check runs of headRefOid"
if grep -q "ccr/review_threads" "$FAKE_GH_LOG"; then fail "switches the PR information to REST too"; else pass; fi
checks "[$PASS_CHECK]" "" 0

done_testing
