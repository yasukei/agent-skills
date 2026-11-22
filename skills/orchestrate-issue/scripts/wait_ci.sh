#!/usr/bin/env bash
# Wait for CI on a PR's head and check for conflicts, then print the result as JSON.
#
#   wait_ci.sh <PR number> <OWNER/REPO> [--mergeability-only] [--interval SECONDS]
#              [--register-timeout SECONDS] [--timeout SECONDS]
#
# It reads check runs and commit statuses through REST, with Actions jobs as a fallback if check
# runs return HTTP 403. Run it once in the background and read its output when it exits.
#
# Output: {"state": "...", "sha": "...", "mergeable": true|false|null, "failing": [{"name": ..., "url": ...}],
#          "checks_source": "check-runs"|"actions"|null}
#   success  every check run and status passed
#   failure  at least one failed (listed in "failing")
#   none     nothing was registered within --register-timeout (default 300 s): the repository may have no CI
#   timeout  CI was still running after --timeout (default 3600 s)
#   no_conflict  the mergeability-only check found no conflict
#   conflicting  the PR conflicts with the base branch
#   mergeability_timeout  GitHub did not return a boolean after five attempts
# Exit status: 0 for success, none or no_conflict, 1 for failure, 3 for either timeout, 4 for conflicting.
# Exit 2 for a usage error, GitHub API error, or changed PR head.
# On a usage or API error, report it and stop. Only explicit results establish "no CI" or "no conflict".
# For a changed head, start a fresh wait.
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
checks_source=""

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
  jq -c --arg state "$1" --arg sha "$sha" --argjson mergeable "$mergeable" \
    --arg checks_source "$checks_source" \
    '{state: $state, sha: $sha, mergeable: $mergeable, failing: .,
      checks_source: ($checks_source | select(length > 0) // null)}' <<<"$2"
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

check_run_entries() {
  local wf_raw checks workflows
  # Workflow name and event are not in check runs. If the lookup fails, keep check suites separate.
  wf_raw="$(gh api --paginate "$workflows_path" 2>/dev/null)" || wf_raw='{"workflow_runs": []}'
  checks="$(jq -sc '[.[].check_runs[]]' <<<"$1")" || return
  workflows="$(jq -sc '[.[].workflow_runs[]]' <<<"$wf_raw")" || return
  jq -cs '
    (.[1] | map({key: (.check_suite_id | tostring), value: {name, event}}) | from_entries) as $workflow
    | .[0][]
    | (.check_suite.id | tostring) as $suite
    | {started: (.started_at // ""), run: {name, status, conclusion, html_url},
       key: (if $workflow[$suite] then [.name, $workflow[$suite].name, $workflow[$suite].event]
             else [.name, "", "", $suite] end)}' <<<"$checks"$'\n'"$workflows"
}

action_job_entries() {
  local response workflows workflow run_id jobs_path
  # --paginate prints one JSON object per page. Validate the arrays before treating them as empty.
  response="$(gh api --paginate "$workflows_path")" || api_error "$workflows_path"
  workflows="$(jq -cs '
    if length > 0 and all(.[]; (.workflow_runs | type) == "array")
    then .[].workflow_runs[] | {id, name, event, status, run_started_at, created_at}
    else error("expected workflow runs")
    end' <<<"$response")" || api_error "$workflows_path"
  while IFS= read -r workflow; do
    [ -n "$workflow" ] || continue
    run_id="$(jq -er '.id | numbers' <<<"$workflow")" || api_error "missing run ID in $workflows_path"
    jobs_path="repos/${repo}/actions/runs/${run_id}/jobs?filter=latest&per_page=100"
    response="$(gh api --paginate "$jobs_path")" || api_error "$jobs_path"
    # Use the run's timestamp for queued jobs whose start time is not available yet.
    jq -cs --argjson workflow "$workflow" '
      if length > 0 and all(.[]; (.jobs | type) == "array")
      then [.[].jobs[]]
      else error("expected jobs")
      end
      # A workflow can register before its jobs. Give it a separate key so it counts as pending.
      | if length == 0 and ($workflow.status // "completed") != "completed" then
          {key: [$workflow.id], started: "", run: {status: $workflow.status}}
        else
          .[]
          | {started: (.started_at // $workflow.run_started_at // $workflow.created_at // ""),
             run: {name, status, conclusion, html_url}, key: [.name, $workflow.name, $workflow.event]}
        end' <<<"$response" || api_error "$jobs_path"
  done <<<"$workflows"
}

read_pull
if [ "$mergeability_only" = true ]; then
  finish_with_mergeability no_conflict '[]' 0
fi

check_runs_path="repos/${repo}/commits/${sha}/check-runs"
workflows_path="repos/${repo}/actions/runs?head_sha=${sha}&per_page=100"
check_runs_error="$(mktemp)" || api_error "could not create a file for check-runs errors"
trap 'rm -f "$check_runs_error"' EXIT

SECONDS=0
while :; do
  if [ "$mergeable" = false ]; then
    emit_result conflicting '[]' 4
  fi

  if runs_raw="$(gh api --paginate "$check_runs_path?per_page=100" 2>"$check_runs_error")"; then
    cat "$check_runs_error" >&2
    checks_source=check-runs
    entries="$(check_run_entries "$runs_raw")" || api_error "invalid response for $check_runs_path"
  elif grep -Eq '(^|[ (])HTTP 403\)?$' "$check_runs_error"; then
    checks_source=actions
    entries="$(action_job_entries)" || exit 2
  else
    cat "$check_runs_error" >&2
    api_error "$check_runs_path"
  fi
  status_raw="$(gh api --paginate "repos/${repo}/commits/${sha}/status?per_page=100")" ||
    api_error "repos/${repo}/commits/${sha}/status"
  # Keep the most recently started check per name, workflow and event, preserving input order for ties.
  runs="$(jq -s '
    to_entries | map(.value + {i: .key})
    | group_by(.key) | map(max_by([.started, -.i])) | sort_by(.i) | map(.run)' <<<"$entries")"
  # The combined status already holds the latest status per context. Its own "state" is "pending"
  # when no status exists at all, so only the individual statuses are read.
  statuses="$(jq -cs '[.[].statuses[]]' <<<"$status_raw")" ||
    api_error "invalid response for repos/${repo}/commits/${sha}/status"

  ci="$(jq -cs '
    .[0] as $runs | .[1] as $statuses
    | if ($runs | length) + ($statuses | length) == 0 then {state: "none"}
      elif any($runs[]; .status != "completed") or any($statuses[]; .state == "pending")
      then {state: "pending"}
      else
        ([$runs[] | select(.conclusion as $c | ["success", "neutral", "skipped"] | index($c) | not)
                  | {name, url: .html_url}]
         + [$statuses[] | select(.state == "failure" or .state == "error")
                        | {name: .context, url: .target_url}]) as $failing
        | if $failing == [] then {state: "success"} else {state: "failure", failing: $failing} end
      end' <<<"$runs"$'\n'"$statuses")"
  case "$(jq -r .state <<<"$ci")" in
    none)
      if [ "$SECONDS" -ge "$register_timeout" ]; then
        finish none '[]' 0
      fi
      ;;
    success) finish success '[]' 0 ;;
    failure) finish failure "$(jq -c .failing <<<"$ci")" 1 ;;
  esac

  if [ "$SECONDS" -ge "$timeout" ]; then
    finish timeout '[]' 3
  fi
  sleep "$interval"
  read_pull
done
