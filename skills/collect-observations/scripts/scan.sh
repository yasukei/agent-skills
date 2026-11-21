#!/usr/bin/env bash
# Tell, for each PR, whether its observations comment is already collected into a log issue.
#   scan.sh OWNER/REPO [--log ISSUE] PR...
#
# A PR's observations comment is the comment orchestrate-issue posts with <!-- orchestrate-issue:observations -->.
# Candidate logs are the issues in the same repository that the PR's timeline lists as cross-references
# (GitHub adds one when a log comment mentions the PR), plus the --log issue. A candidate counts as a log
# only if its body has <!-- collect-observations:log -->, and a comment counts as collected only if a
# comment of that log has <!-- collect-observations:source pr=<PR> comment=<comment id> -->.
# A cross-reference alone is not enough: any issue that mentions the PR creates one.
#
# Prints one JSON line per PR, in the order given:
#   {"pr", "title", "url", "merged", "status",
#    "observations": [{"id", "html_url"}],          observations comments on the PR
#    "collected": [{"comment", "log", "log_comment"}], where each of them is collected
#    "unmarked_mentions": [N...]}                  issues that mention the PR but have no log marker
# status: not-merged  | no-comment (merged, no observations comment)
#       | uncollected | partial (some comments collected) | collected
# Exit status: 0 on success, 2 on a usage or GitHub API error, or when --log is a PR.
# Repository names are compared in lowercase, because GitHub accepts any casing in OWNER/REPO
# but returns its own in repository_url.
# Only REST endpoints are used, so it works where GraphQL returns HTTP 403.
set -euo pipefail

usage() {
  echo "usage: $0 OWNER/REPO [--log ISSUE] PR..." >&2
  exit 2
}

fail() {
  echo "$0: $*" >&2
  exit 2
}

is_number() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

[ $# -ge 1 ] || usage
repo="$1"
shift
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage

log=""
prs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --log)
      if [ $# -lt 2 ] || ! is_number "$2"; then usage; fi
      log="$2"
      shift 2
      ;;
    *)
      is_number "${1#\#}" || usage
      prs+=("${1#\#}")
      shift
      ;;
  esac
done
[ "${#prs[@]}" -gt 0 ] || usage

OBS_MARKER='<!-- orchestrate-issue:observations -->'
LOG_MARKER='<!-- collect-observations:log -->'
SOURCE_RE='<!-- collect-observations:source pr=([0-9]+) comment=([0-9]+) -->'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# get <path> <out file>: one REST object
get() {
  gh api "$1" >"$2" 2>"$work/err" || fail "gh api $1: $(cat "$work/err")"
}

# list <path> <out file>: every page of a REST list as one JSON array
list() {
  gh api --paginate "$1" >"$work/pages" 2>"$work/err" || fail "gh api $1: $(cat "$work/err")"
  jq -s 'add // []' "$work/pages" >"$2" || fail "gh api $1: not a JSON list"
}

# load_log <issue>: write $work/log_<issue>.json once: {number, log, sources: [{pr, comment, log_comment}]}
load_log() {
  local n="$1" file="$work/log_$1.json"
  [ -f "$file" ] && return
  get "repos/$repo/issues/$n" "$work/issue"
  if jq -e --arg m "$LOG_MARKER" '.pull_request == null and (.body // "" | contains($m))' \
    "$work/issue" >/dev/null; then
    list "repos/$repo/issues/$n/comments?per_page=100" "$work/log_comments"
    jq -c --argjson n "$n" --arg re "$SOURCE_RE" '{number: $n, log: true, sources: [
      .[] | .html_url as $url | (.body // "") | [scan($re)][]
      | {pr: (.[0] | tonumber), comment: (.[1] | tonumber), log_comment: $url}]}' \
      "$work/log_comments" >"$file"
  else
    jq -cn --argjson n "$n" '{number: $n, log: false, sources: []}' >"$file"
  fi
}

# The issues endpoint also returns PRs, and comments and body edits work on them too, so a PR given as
# the log would be written to
if [ -n "$log" ]; then
  get "repos/$repo/issues/$log" "$work/issue"
  if jq -e '.pull_request != null' "$work/issue" >/dev/null; then
    fail "--log $log is a pull request, not an issue"
  fi
fi

for pr in "${prs[@]}"; do
  get "repos/$repo/pulls/$pr" "$work/pull"
  list "repos/$repo/issues/$pr/comments?per_page=100" "$work/comments"
  list "repos/$repo/issues/$pr/timeline?per_page=100" "$work/timeline"

  candidates="$(jq -r --arg api "https://api.github.com/repos/$repo" --arg log "$log" '
    ($api | ascii_downcase) as $api
    | [.[] | select(.event == "cross-referenced") | .source.issue // empty
     | select(.pull_request == null and (.repository_url // "" | ascii_downcase) == $api) | .number]
    + (if $log == "" then [] else [$log | tonumber] end) | unique | .[]' "$work/timeline")"
  logs=()
  for n in $candidates; do
    load_log "$n"
    logs+=("$work/log_$n.json")
  done
  if [ "${#logs[@]}" -gt 0 ]; then
    jq -s . "${logs[@]}" >"$work/logs"
  else
    echo '[]' >"$work/logs"
  fi

  jq -c --argjson pr "$pr" --arg m "$OBS_MARKER" --slurpfile logs "$work/logs" --slurpfile c "$work/comments" '
    ([$c[0][] | select(.body // "" | contains($m)) | {id, html_url}]) as $obs
    | ([$logs[0][] | .number as $log | .sources[] | select(.pr == $pr)
        | . as $s | select([$obs[].id] | index($s.comment))
        | {comment, log: $log, log_comment}]) as $collected
    | ([$collected[].comment] | unique | length) as $done
    | {pr: .number, title, url: .html_url, merged,
       status: (if .merged != true then "not-merged"
                elif ($obs | length) == 0 then "no-comment"
                elif $done == 0 then "uncollected"
                elif $done < ($obs | length) then "partial"
                else "collected" end),
       observations: $obs, collected: $collected,
       unmarked_mentions: [$logs[0][] | select(.log | not) | .number]}' "$work/pull"
done
