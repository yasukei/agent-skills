#!/usr/bin/env bash
# Wait until CI on a PR's head commit finishes, then print the result as JSON.
#
#   wait_ci.sh <PR number> <OWNER/REPO> [--interval SECONDS] [--register-timeout SECONDS] [--timeout SECONDS]
#
# It reads both check runs and commit statuses through REST, so it also works where GraphQL returns
# HTTP 403. It loops by itself; run it once in the background and read its output when it exits.
#
# Output: {"state": "success|failure|none|timeout", "sha": "...", "failing": [{"name": ..., "url": ...}]}
#   success  every check run and status passed
#   failure  at least one failed (listed in "failing")
#   none     nothing was registered within --register-timeout (default 300 s): the repository may have no CI
#   timeout  CI was still running after --timeout (default 3600 s)
# Exit status: 0 for success or none, 1 for failure, 3 for timeout, 2 for usage or GitHub API errors.
# An API error stops the wait with status 2 and is never read as "no CI".
set -euo pipefail

usage() {
  echo "usage: $0 <PR number> <OWNER/REPO> [--interval SECONDS] [--register-timeout SECONDS] [--timeout SECONDS]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
pr="$1"
repo="$2"
shift 2
interval=30
register_timeout=300
timeout=3600
while [ $# -gt 0 ]; do
  case "$1" in
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

api_error() {
  echo "wait_ci.sh: GitHub API request failed: $1" >&2
  exit 2
}

pull_json="$(gh api "repos/${repo}/pulls/${pr}")" || api_error "repos/${repo}/pulls/${pr}"
sha="$(jq -r '.head.sha // empty' <<<"$pull_json")"
[ -n "$sha" ] || api_error "no head SHA for PR ${pr}"

finish() {
  # finish <state> <failing JSON array> <exit status>
  jq -cn --arg state "$1" --arg sha "$sha" --argjson failing "$2" '{state: $state, sha: $sha, failing: $failing}'
  exit "$3"
}

SECONDS=0
while :; do
  # --paginate prints one JSON object per page; jq -s merges them.
  runs_raw="$(gh api --paginate "repos/${repo}/commits/${sha}/check-runs?per_page=100")" ||
    api_error "repos/${repo}/commits/${sha}/check-runs"
  status_raw="$(gh api --paginate "repos/${repo}/commits/${sha}/status?per_page=100")" ||
    api_error "repos/${repo}/commits/${sha}/status"
  runs="$(jq -s '[.[].check_runs[]]' <<<"$runs_raw")"
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
done
