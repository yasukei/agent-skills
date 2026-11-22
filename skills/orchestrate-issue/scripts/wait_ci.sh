#!/usr/bin/env bash
# Wait for CI on a PR's head and check for conflicts, then print the result as JSON.
#
#   wait_ci.sh <PR number> <OWNER/REPO> [--mergeability-only] [--interval SECONDS]
#              [--register-timeout SECONDS] [--timeout SECONDS]
#
# It reads both check runs and commit statuses through REST, so it also works where GraphQL returns
# HTTP 403. It loops by itself; run it once in the background and read its output when it exits.
#
# Output: {"state": "...", "sha": "...", "mergeable": true|false|null, "failing": [{"name": ..., "url": ...}]}
#   success  every check run and status passed
#   failure  at least one failed (listed in "failing")
#   none     nothing was registered within --register-timeout (default 300 s): the repository may have no CI
#   timeout  CI was still running after --timeout (default 3600 s)
#   no_conflict  the mergeability-only check found no conflict
#   conflicting  the PR conflicts with the base branch
#   mergeability_timeout  GitHub did not return a boolean after five attempts
# Exit status: 0 for success, none or no_conflict, 1 for failure, 3 for either timeout, 4 for conflicting.
# Usage and GitHub API errors, including a changed PR head, exit with status 2.
set -euo pipefail

usage() {
  echo "usage: $0 <PR number> <OWNER/REPO> [--mergeability-only] [--interval SECONDS] [--register-timeout SECONDS] [--timeout SECONDS]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
pr="$1"
repo="$2"
shift 2
interval=30
register_timeout=300
timeout=3600
mergeability_only=false
while [ $# -gt 0 ]; do
  case "$1" in
    --mergeability-only) mergeability_only=true; shift ;;
    --interval) [ $# -ge 2 ] || usage; interval="$2"; shift 2 ;;
    --register-timeout) [ $# -ge 2 ] || usage; register_timeout="$2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || usage; timeout="$2"; shift 2 ;;
    *) usage ;;
  esac
done
for n in "$pr" "$interval" "$register_timeout" "$timeout"; do
  case "$n" in
    '' | *[!0-9]*) usage ;;
  esac
done
merge_interval=2
if [ "$interval" -lt "$merge_interval" ]; then merge_interval="$interval"; fi

api_error() {
  echo "wait_ci.sh: GitHub API request failed: $1" >&2
  exit 2
}

pull_path="repos/${repo}/pulls/${pr}"
sha=""

read_pull() {
  local pull_json head
  pull_json="$(gh api "$pull_path")" || api_error "$pull_path"
  head="$(jq -r '.head.sha // empty' <<<"$pull_json")" || api_error "invalid response for PR ${pr}"
  [ -n "$head" ] || api_error "no head SHA for PR ${pr}"
  if [ -n "$sha" ] && [ "$head" != "$sha" ]; then
    echo "wait_ci.sh: PR ${pr} head changed while waiting from ${sha} to ${head}" >&2
    exit 2
  fi
  sha="$head"
  mergeable="$(jq -c '.mergeable' <<<"$pull_json")" || api_error "invalid response for PR ${pr}"
  case "$mergeable" in
    true | false | null) ;;
    *) api_error "invalid mergeable value for PR ${pr}" ;;
  esac
}

emit_result() {
  jq -cn --arg state "$1" --arg sha "$sha" --argjson mergeable "$mergeable" --argjson failing "$2" \
    '{state: $state, sha: $sha, mergeable: $mergeable, failing: $failing}'
  exit "$3"
}

finish_with_mergeability() {
  local attempt
  # GitHub computes mergeability asynchronously. Only the boolean indicates a conflict.
  for attempt in 1 2 3 4 5; do
    case "$mergeable" in
      true) emit_result "$@" ;;
      false) emit_result conflicting "$2" 4 ;;
    esac
    [ "$attempt" -lt 5 ] || break
    sleep "$merge_interval"
    read_pull
  done
  emit_result mergeability_timeout "$2" 3
}

finish() {
  # Refresh after CI to catch changes to the base branch while CI was running.
  read_pull
  finish_with_mergeability "$@"
}

read_pull
if [ "$mergeability_only" = true ]; then
  finish_with_mergeability no_conflict '[]' 0
fi

SECONDS=0
while :; do
  if [ "$mergeable" = false ]; then
    emit_result conflicting '[]' 4
  fi

  # --paginate prints one JSON object per page; jq -s merges them.
  runs_raw="$(gh api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100")" ||
    api_error "repos/${repo}/commits/${sha}/check-runs"
  status_raw="$(gh api --paginate "repos/${repo}/commits/${sha}/status?per_page=100")" ||
    api_error "repos/${repo}/commits/${sha}/status"
  # Workflow name and event are not in check runs; look them up in the workflow runs. If that fails, each check
  # suite stays separate, which can keep an old failure but never hides a current one.
  wf_raw="$(gh api --paginate "repos/${repo}/actions/runs?head_sha=${sha}&per_page=100" 2>/dev/null)" ||
    wf_raw='{"workflow_runs": []}'
  # When a workflow is re-run on the same commit, check-runs also returns same-named checks from the old check
  # suite. Like gh pr checks, keep only the most recently started one per check name, workflow name and event.
  runs="$(jq -n --argjson raw "$(jq -s '[.[].check_runs[]]' <<<"$runs_raw")" \
    --argjson wf "$(jq -s '[.[].workflow_runs[]]' <<<"$wf_raw")" '
    ($wf | map({key: (.check_suite_id | tostring), value: {name, event}}) | from_entries) as $workflow
    | [$raw | to_entries[] | .key as $i | .value
       | (.check_suite.id | tostring) as $suite
       | {i: $i, started: (.started_at // ""), run: .,
          key: (if $workflow[$suite] then [.name, $workflow[$suite].name, $workflow[$suite].event]
                else [.name, "", "", $suite] end)}]
    | group_by(.key) | map(max_by([.started, -.i])) | sort_by(.i) | map(.run)')"
  # The combined status already holds the latest status per context. Its own "state" is "pending"
  # when no status exists at all, so only the individual statuses are read.
  statuses="$(jq -s '[.[].statuses[]]' <<<"$status_raw")"

  registered="$(jq -n --argjson r "$runs" --argjson s "$statuses" '($r | length) + ($s | length)')"
  pending="$(jq -n --argjson r "$runs" --argjson s "$statuses" \
    '([$r[] | select(.status != "completed")] | length) + ([$s[] | select(.state == "pending")] | length)')"

  if [ "$registered" -eq 0 ]; then
    if [ "$SECONDS" -ge "$register_timeout" ]; then
      finish none '[]' 0
    fi
  elif [ "$pending" -eq 0 ]; then
    failing="$(jq -n --argjson r "$runs" --argjson s "$statuses" '
      [$r[] | select(.conclusion as $c | ["success", "neutral", "skipped"] | index($c) | not)
            | {name, url: .html_url}]
      + [$s[] | select(.state == "failure" or .state == "error") | {name: .context, url: .target_url}]')"
    if [ "$(jq 'length' <<<"$failing")" -eq 0 ]; then
      finish success '[]' 0
    fi
    finish failure "$failing" 1
  fi

  if [ "$SECONDS" -ge "$timeout" ]; then
    finish timeout '[]' 3
  fi
  sleep "$interval"
  read_pull
done
