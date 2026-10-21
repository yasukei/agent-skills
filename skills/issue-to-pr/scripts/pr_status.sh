#!/usr/bin/env bash
# Print the state of a PR (CI, reviews, review threads, PR comments) as one JSON object.
# Usage: pr_status.sh <PR number> [owner/repo]
#   Without owner/repo, the repository of the current directory is used.
# Requires: gh (authenticated), jq
#
# Normally uses GraphQL and gh pr checks. Where GraphQL is rejected with 403
# (Claude Code on the web, etc.), it switches to the REST API and the CCR route for review threads
# (GET /repos/{owner}/{repo}/pulls/{n}/ccr/review_threads).
# With an old gh whose gh pr checks has no --json (such as 2.46), only CI is fetched through REST.
# The JSON has the same shape on both paths, except that on the REST path
# reviewDecision is always null and threads[].id (the GraphQL thread ID) is null.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <PR number> [owner/repo]" >&2
  exit 1
fi

PR="$1"
# gh repo view uses GraphQL, so resolve the current repository through REST
# shellcheck disable=SC2016
REPO="${2:-$(gh api 'repos/{owner}/{repo}' --jq .full_name)}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

TMP="$(mktemp -d)"
API=graphql
# When the REST path fails, also print the GraphQL error that triggered the switch,
# so the cause can be traced when the 403 was not a GraphQL rejection (SAML SSO, etc.)
on_exit() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$API" = rest ]; then
    echo "Failed to fetch through REST. The GraphQL error before switching to REST:" >&2
    cat "$TMP/graphql.err" >&2
  fi
  rm -rf "$TMP"
}
trap on_exit EXIT

# $owner etc. are GraphQL variables, not shell expansions
# shellcheck disable=SC2016
QUERY='
query($owner: String!, $name: String!, $pr: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      url
      state
      isDraft
      mergeable
      reviewDecision
      author { login }
      headRefName
      headRefOid
      baseRefName
      reviews(last: 50) {
        nodes { author { login __typename } state submittedAt body }
      }
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 50) {
            nodes { databaseId author { login __typename } body createdAt url }
          }
        }
      }
      comments(last: 50) {
        nodes { databaseId author { login __typename } body createdAt url }
      }
    }
  }
}'

# Convert the REST responses into the same shape as GraphQL's pullRequest and print it.
# Arguments: files with the JSON of the PR, reviews, review comments, PR comments and the CCR route's threads
rest_pr_json() {
  jq -n --slurpfile pr "$1" --slurpfile reviews "$2" --slurpfile comments "$3" \
    --slurpfile issueComments "$4" --slurpfile threads "$5" '
    $pr[0] as $pr
    | def author: { login: (.user.login // "ghost"), __typename: (if .user.type == "Bot" then "Bot" else "User" end) };
      def node: { databaseId: .id, author: author, body: (.body // ""), createdAt: .created_at, url: .html_url };
    ($comments[0] | map({ key: (.id | tostring), value: node }) | from_entries) as $byId
    | {
        url: $pr.html_url,
        state: (if $pr.merged then "MERGED" elif $pr.state == "closed" then "CLOSED" else "OPEN" end),
        isDraft: $pr.draft,
        mergeable: (if $pr.mergeable == true then "MERGEABLE"
                    elif $pr.mergeable == false then "CONFLICTING"
                    else "UNKNOWN" end),
        reviewDecision: null,
        author: { login: $pr.user.login },
        headRefName: $pr.head.ref,
        baseRefName: $pr.base.ref,
        reviews: { nodes: [ $reviews[0][] | { author: author, state, submittedAt: .submitted_at, body: (.body // "") } ] },
        # The CCR route returns only comment IDs per thread, so look up bodies etc. in the review comment list.
        # Drop comments missing from the list (e.g. from a pending review), and threads left with no comments
        reviewThreads: { nodes: [ $threads[0][] | {
          id: null, isResolved: .resolved, isOutdated: .outdated, path, line,
          comments: { nodes: [ .comment_ids[] | tostring | $byId[.] | select(. != null) ] }
        } | select(.comments.nodes | length > 0) ] },
        comments: { nodes: [ $issueComments[0][] | node ] }
      }'
}

# Convert the REST checks (check runs and commit statuses) into the same shape as
# gh pr checks --json name,state,bucket,link,workflow and print them. Bucketing and deduplication follow gh pr checks.
# Arguments: files with the JSON of the check runs, commit statuses and workflow runs
rest_checks_json() {
  jq -n --slurpfile runs "$1" --slurpfile statuses "$2" --slurpfile workflowRuns "$3" '
    def bucket:
      if . == "SUCCESS" then "pass"
      elif IN("SKIPPED", "NEUTRAL") then "skipping"
      elif IN("FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE") then "fail"
      elif . == "CANCELLED" then "cancel"
      else "pending" end;
    ($workflowRuns[0] | map({ key: (.check_suite_id | tostring), value: { name, event } }) | from_entries) as $workflow
    # When a workflow is re-run on the same commit, check-runs also returns same-named checks from the old check suite.
    # Like gh pr checks, keep only the most recently started one per check name, workflow name and event.
    # A check suite whose workflow run is unknown (fetch failure, an app other than Actions, etc.) is treated as
    # separate checks per check suite, so it does not hide failures in another workflow
    | [ $runs[0] | to_entries[]
        | .key as $i | .value
        | (.check_suite.id | tostring) as $suite
        | ($workflow[$suite] // { name: "", event: "" }) as $wf
        | ((if .status == "completed" then .conclusion else .status end) // "" | ascii_upcase) as $state
        | { i: $i,
            key: (if $workflow[$suite] then [.name, $wf.name, $wf.event] else [.name, "", "", $suite] end),
            startedAt: (.started_at // ""),
            check: { name, state: $state, bucket: ($state | bucket), link: (.details_url // .html_url // ""),
                     workflow: $wf.name } } ]
    | group_by(.key) | map(max_by([.startedAt, -.i])) | sort_by(.i) | map(.check)
    # Commit statuses come back with only the latest per context
    + [ $statuses[0][]
        | (.state | ascii_upcase) as $state
        | { name: .context, state: $state, bucket: ($state | bucket), link: (.target_url // ""), workflow: "" } ]'
}

# gh api --paginate prints the JSON of each page concatenated. Join the arrays at <field> (the whole page if omitted)
# of each page into one array
paginate() {
  local field="$1"
  shift
  gh api --paginate "$@" | jq -s --arg f "$field" 'map(if $f == "" then . else .[$f] end) | add // []'
}

# Fetch the commit's checks through REST and write them to $TMP/checks.json in the same shape as gh pr checks --json.
# Call it directly, not inside a command substitution, so a fetch failure stops the script
# Arguments: repos/<owner>/<repo>, the commit SHA
rest_checks() {
  local base="$1" sha="$2"
  paginate check_runs "$base/commits/$sha/check-runs?per_page=100" >"$TMP/check-runs.json"
  paginate statuses "$base/commits/$sha/status?per_page=100" >"$TMP/statuses.json"
  # Workflow name and event are not in check runs, so look them up in the workflow runs. Use an empty string if unavailable
  paginate workflow_runs "$base/actions/runs?head_sha=$sha&per_page=100" >"$TMP/workflow-runs.json" 2>/dev/null \
    || echo '[]' >"$TMP/workflow-runs.json"
  rest_checks_json "$TMP/check-runs.json" "$TMP/statuses.json" "$TMP/workflow-runs.json" >"$TMP/checks.json"
}

# Try GraphQL first, and switch to REST when it is rejected with 403
if gh api graphql -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" -F pr="$PR" \
  >"$TMP/graphql.json" 2>"$TMP/graphql.err"; then
  PR_JSON="$(jq '.data.repository.pullRequest' "$TMP/graphql.json")"

  # CI. gh pr checks exits with 1 on failure and 8 on pending, but prints JSON in both cases, so
  # decide by the output, not the exit status. Treat only "no checks at all" as an empty array
  CHECKS_RC=0
  CHECKS_JSON="$(gh pr checks "$PR" --repo "$REPO" --json name,state,bucket,link,workflow 2>"$TMP/checks.err")" || CHECKS_RC=$?
  if [ -n "$CHECKS_JSON" ] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$CHECKS_JSON"; then
    :
  elif grep -q "no checks reported" "$TMP/checks.err"; then
    CHECKS_JSON='[]'
  elif grep -q "unknown flag: --json" "$TMP/checks.err"; then
    # With an old gh whose gh pr checks has no --json, fetch through REST
    rest_checks "repos/$OWNER/$NAME" "$(jq -r '.headRefOid' <<<"$PR_JSON")"
    CHECKS_JSON="$(cat "$TMP/checks.json")"
  else
    echo "gh pr checks failed (exit status $CHECKS_RC):" >&2
    cat "$TMP/checks.err" >&2
    exit 1
  fi
elif grep -Eq 'HTTP 403|GraphQL is not available' "$TMP/graphql.err"; then
  API=rest
  BASE="repos/$OWNER/$NAME"
  gh api "$BASE/pulls/$PR" >"$TMP/pr.json"
  paginate "" "$BASE/pulls/$PR/reviews?per_page=100" >"$TMP/reviews.json"
  paginate "" "$BASE/pulls/$PR/comments?per_page=100" >"$TMP/comments.json"
  paginate "" "$BASE/issues/$PR/comments?per_page=100" >"$TMP/issue-comments.json"
  gh api "$BASE/pulls/$PR/ccr/review_threads" >"$TMP/threads.json"
  PR_JSON="$(rest_pr_json "$TMP/pr.json" "$TMP/reviews.json" "$TMP/comments.json" \
    "$TMP/issue-comments.json" "$TMP/threads.json")"

  rest_checks "$BASE" "$(jq -r '.head.sha' "$TMP/pr.json")"
  CHECKS_JSON="$(cat "$TMP/checks.json")"
else
  echo "Failed to fetch the PR through GraphQL:" >&2
  cat "$TMP/graphql.err" >&2
  exit 1
fi

# Marker on comments this skill posts, so the author and reviewer can be told apart even on the same account
MARKER='<!-- issue-to-pr -->'
# Marker by which the reviewer states "review finished with no findings" (the completion signal on the same account)
COMPLETE_MARKER='<!-- review-complete -->'

jq -n --argjson pr "$PR_JSON" --argjson checks "$CHECKS_JSON" \
  --arg marker "$MARKER" --arg complete "$COMPLETE_MARKER" '
  ($pr.author.login) as $author
  | (if ($checks | length) == 0 then "none"
     elif any($checks[]; .bucket == "fail" or .bucket == "cancel") then "failing"
     elif any($checks[]; .bucket == "pending") then "pending"
     else "passing" end) as $ci
  # Reviewer activity (items without the marker). Excludes the replies of this skill itself and the PR body.
  # Replying to a thread creates a COMMENTED review with an empty body in the name of the author, so exclude those too.
  # Bots (Copilot, coverage reports, etc.) never Approve or signal completion, so they do not count as reviewers
  | def human: (.author.__typename // "User") != "Bot" and (.author.login // "" | endswith("[bot]") | not);
    def notMine: .body // "" | contains($marker) | not;
  [ $pr.reviews.nodes[]
      | select(human and notMine and ((.body // "") != "" or .state != "COMMENTED"))
      | . + { at: .submittedAt } ] as $reviewerReviews
  | [ $pr.reviewThreads.nodes[] | select(.comments.nodes[0] | human and notMine) ] as $reviewerThreads
  | [ $pr.reviewThreads.nodes[].comments.nodes[] | select(human and notMine) | . + { at: .createdAt } ] as $reviewerThreadComments
  | [ $pr.comments.nodes[] | select(human and notMine) | . + { at: .createdAt } ] as $reviewerIssueComments
  | ($reviewerReviews + $reviewerThreadComments + $reviewerIssueComments) as $reviewerActivity
  | (($reviewerActivity | length) > 0) as $activity
  | any($reviewerActivity[]; .author.login != $author) as $hasOther
  | ([ $pr.reviews.nodes[] | select(human and .author.login != $author and .state != "COMMENTED") ]
     | group_by(.author.login) | map(max_by(.submittedAt))) as $latestOthers
  | ([ $reviewerThreads[] | select(.isResolved | not) ] | length) as $unresolvedReviewer
  # The completion marker counts only when there is no reviewer activity (a question, etc.) after it
  | ([ ($reviewerReviews + $reviewerIssueComments)[] | select(.body // "" | contains($complete)) | .at ] | max) as $completedAt
  | ($completedAt != null and all($reviewerActivity[]; .at <= $completedAt)) as $explicit
  | (if $pr.state == "MERGED" then ["merged", "The PR was merged"]
     elif $pr.state == "CLOSED" then ["closed", "The PR was closed"]
     elif $ci == "failing" then ["ci_failing", "CI is failing"]
     elif $ci == "pending" then ["ci_pending", "CI is running"]
     elif $pr.mergeable == "CONFLICTING" then ["conflicting", "The PR conflicts with the base branch"]
     elif $pr.mergeable != "MERGEABLE" then ["mergeable_unknown", "GitHub is still computing whether the PR can be merged"]
     elif ($activity | not) then ["waiting_for_review", "No reviewer activity yet"]
     elif $hasOther then
       (if ($latestOthers | length) > 0 and all($latestOthers[]; .state == "APPROVED")
        then ["ready", "The latest review from a non-author account is Approve"]
        else ["review_in_progress", "Waiting for Approve from a non-author account"] end)
     elif $unresolvedReviewer > 0 then ["review_in_progress", "There are unresolved review threads"]
     elif ($reviewerThreads | length) > 0 then ["ready", "All review threads are resolved"]
     elif $explicit then ["ready", "The reviewer signaled review complete with no findings"]
     else ["review_in_progress", "No review completion signal yet (all threads resolved or the completion marker)"] end
    ) as $v
  | {
      url: $pr.url,
      state: $pr.state,
      mergeable: $pr.mergeable,
      reviewDecision: $pr.reviewDecision,
      author: $author,
      head: $pr.headRefName,
      base: $pr.baseRefName,
      # Exit decision. Keep monitoring until done is true (see references/exit-conditions.md)
      verdict: { status: $v[0], done: ($v[0] | IN("ready", "merged", "closed")), reason: $v[1] },
      ci: {
        summary: $ci,
        failing: [ $checks[] | select(.bucket == "fail" or .bucket == "cancel") ],
        pending: [ $checks[] | select(.bucket == "pending") | .name ]
      },
      review: {
        # Whether there is a review, thread comment or PR comment without the marker. false means "waiting for review"
        activity: $activity,
        # Whether a non-author account is reviewing (used by the exit decision)
        mode: (if $hasOther then "other_account" elif $activity then "same_account" else "none" end),
        explicitCompletion: $explicit,
        reviewerThreadCount: ($reviewerThreads | length),
        unresolvedReviewerThreadCount: $unresolvedReviewer
      },
      hasOtherReviewer: $hasOther,
      latestReviewByOthers: $latestOthers,
      reviews: $pr.reviews.nodes,
      unresolvedThreadCount: ([ $pr.reviewThreads.nodes[] | select(.isResolved | not) ] | length),
      threads: [
        $pr.reviewThreads.nodes[] | {
          id, isResolved, isOutdated, path, line,
          rootCommentId: .comments.nodes[0].databaseId,
          comments: .comments.nodes,
          # If the last comment has no marker, a reviewer comment may still be unanswered
          lastCommentByMe: (.comments.nodes[-1].body | contains($marker))
        }
      ],
      issueComments: [ $pr.comments.nodes[] | . + { byMe: (.body | contains($marker)) } ]
    }
'
