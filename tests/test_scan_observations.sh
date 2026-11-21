#!/usr/bin/env bash
# Tests for skills/collect-observations/scripts/scan.sh.
# A fake gh (tests/fake-bin/gh) goes first in PATH and answers REST calls from files, so the tests do not depend
# on GitHub authentication or the network.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/skills/collect-observations/scripts/scan.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export PATH="$ROOT/tests/fake-bin:$PATH"
export FAKE_REST_DIR="$WORK/rest"

OBS='<!-- orchestrate-issue:observations -->'
LOG='<!-- collect-observations:log -->'
API=https://api.github.com/repos

# Start each case with no responses
reset() {
  rm -rf "$FAKE_REST_DIR"
  mkdir -p "$FAKE_REST_DIR"
}

# write <path> <json>: the response of gh api <path>
write() {
  printf '%s\n' "$2" >"$FAKE_REST_DIR/$(printf '%s' "$1" | tr / _).json"
}

# pull <number> <merged>: a PR with no comments and an empty timeline
pull() {
  write "repos/o/r/pulls/$1" "{\"number\": $1, \"title\": \"PR $1\", \"html_url\": \"https://github.com/o/r/pull/$1\", \"merged\": $2}"
  write "repos/o/r/issues/$1/comments" '[]'
  write "repos/o/r/issues/$1/timeline" '[]'
}

# comment <id> <body>: one comment object
comment() {
  jq -cn --argjson id "$1" --arg body "$2" '{id: $id, html_url: ("https://github.com/o/r/issues/x#issuecomment-" + ($id | tostring)), body: $body}'
}

# xref <repository> <number> <is pr>: a cross-referenced timeline event
xref() {
  jq -cn --arg repo "$API/$1" --argjson n "$2" --argjson pr "$3" \
    '{event: "cross-referenced", source: {type: "issue", issue: ({number: $n, repository_url: $repo}
      + (if $pr then {pull_request: {}} else {} end))}}'
}

# issue <number> <body> <comments json>: an issue and its comments
issue() {
  write "repos/o/r/issues/$1" "$(jq -cn --argjson n "$1" --arg body "$2" '{number: $n, body: $body}')"
  write "repos/o/r/issues/$1/comments" "$3"
}

source_marker() {
  printf '<!-- collect-observations:source pr=%s comment=%s -->' "$1" "$2"
}

# Run scan.sh and store the results in OUT, ERR and RC
scan() {
  RC=0
  "$SCRIPT" "$@" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# field <line number> <jq filter>: a field of one output line
field() {
  sed -n "${1}p" <<<"$OUT" | jq -c "$2"
}

# ---------------------------------------------------------------------------
t "merged PR with an observations comment that no log mentions"
reset
pull 40 true
write repos/o/r/issues/40/comments "[$(comment 10 hello), $(comment 111 "### PR #40$OBS")]"
scan o/r 40
assert_eq 0 "$RC" "exit status ($ERR)"
assert_eq '"uncollected"' "$(field 1 .status)" "status"
assert_eq '[111]' "$(field 1 '[.observations[].id]')" "observations"
assert_eq '[]' "$(field 1 .unmarked_mentions)" "unmarked mentions"
assert_eq '"https://github.com/o/r/pull/40"' "$(field 1 .url)" "url"

# ---------------------------------------------------------------------------
t "collected in a log found through the cross-reference"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS")]"
write repos/o/r/issues/41/timeline "[{\"event\": \"commented\"}, $(xref o/r 50 false)]"
issue 50 "log body
$LOG" "[$(comment 900 "### PR #41
$(source_marker 41 222)")]"
scan o/r 41
assert_eq 0 "$RC" "exit status ($ERR)"
assert_eq '"collected"' "$(field 1 .status)" "status"
assert_eq '[{"comment":222,"log":50,"log_comment":"https://github.com/o/r/issues/x#issuecomment-900"}]' \
  "$(field 1 .collected)" "collected"

# ---------------------------------------------------------------------------
t "an issue without the log marker does not count, and is reported"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS")]"
write repos/o/r/issues/41/timeline "[$(xref o/r 51 false)]"
issue 51 "mentions #41" "[$(comment 901 "$(source_marker 41 222)")]"
scan o/r 41
assert_eq '"uncollected"' "$(field 1 .status)" "status"
assert_eq '[51]' "$(field 1 .unmarked_mentions)" "unmarked mentions"

# ---------------------------------------------------------------------------
t "a source marker for another PR or another comment does not count"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS")]"
write repos/o/r/issues/41/timeline "[$(xref o/r 50 false)]"
issue 50 "$LOG" "[$(comment 900 "$(source_marker 42 222)
$(source_marker 41 999)")]"
scan o/r 41
assert_eq '"uncollected"' "$(field 1 .status)" "status"
assert_eq '[]' "$(field 1 .collected)" "collected"

# ---------------------------------------------------------------------------
t "cross-references from PRs and from other repositories are ignored"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS")]"
write repos/o/r/issues/41/timeline "[$(xref o/r 52 true), $(xref other/r 53 false)]"
scan o/r 41
assert_eq 0 "$RC" "exit status: neither #52 nor #53 is fetched ($ERR)"
assert_eq '"uncollected"' "$(field 1 .status)" "status"
assert_eq '[]' "$(field 1 .unmarked_mentions)" "unmarked mentions"

# ---------------------------------------------------------------------------
t "--log is read even without a cross-reference"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS")]"
issue 50 "$LOG" "[$(comment 900 "$(source_marker 41 222)")]"
scan o/r --log 50 41
assert_eq '"collected"' "$(field 1 .status)" "status"

# ---------------------------------------------------------------------------
t "some observations comments collected"
reset
pull 41 true
write repos/o/r/issues/41/comments "[$(comment 222 "x$OBS"), $(comment 333 "y$OBS")]"
issue 50 "$LOG" "[$(comment 900 "$(source_marker 41 333)")]"
scan o/r --log 50 41
assert_eq '"partial"' "$(field 1 .status)" "status"
assert_eq '[333]' "$(field 1 '[.collected[].comment]')" "collected"

# ---------------------------------------------------------------------------
t "comments on several pages"
reset
pull 41 true
# gh api --paginate prints one array per page
printf '%s\n%s\n' "[$(comment 1 a)]" "[$(comment 222 "x$OBS")]" >"$FAKE_REST_DIR/repos_o_r_issues_41_comments.json"
scan o/r 41
assert_eq '[222]' "$(field 1 '[.observations[].id]')" "observations"

# ---------------------------------------------------------------------------
t "merged without a comment, not merged, and several PRs in order"
reset
pull 43 true
pull 44 false
write repos/o/r/issues/44/comments "[$(comment 444 "x$OBS")]"
scan o/r 44 '#43'
assert_eq 0 "$RC" "exit status ($ERR)"
assert_eq 2 "$(wc -l <<<"$OUT" | tr -d ' ')" "one line per PR"
assert_eq '[44,"not-merged"]' "$(field 1 '[.pr, .status]')" "first PR"
assert_eq '[43,"no-comment"]' "$(field 2 '[.pr, .status]')" "second PR"

# ---------------------------------------------------------------------------
t "a log is fetched once for several PRs"
reset
pull 41 true
pull 42 true
for pr in 41 42; do
  write "repos/o/r/issues/$pr/comments" "[$(comment "${pr}0" "x$OBS")]"
  write "repos/o/r/issues/$pr/timeline" "[$(xref o/r 50 false)]"
done
issue 50 "$LOG" "[$(comment 900 "$(source_marker 41 410)
$(source_marker 42 420)")]"
export FAKE_GH_LOG="$WORK/gh.log"
: >"$FAKE_GH_LOG"
scan o/r 41 42
unset FAKE_GH_LOG
assert_eq '"collected"' "$(field 1 .status)" "first PR"
assert_eq '"collected"' "$(field 2 .status)" "second PR"
assert_eq 1 "$(grep -c 'repos/o/r/issues/50/comments' "$WORK/gh.log")" "log comments fetched once"

# ---------------------------------------------------------------------------
t "usage errors"
reset
for args in "" "o/r" "notarepo 1" "o/r abc" "o/r --log 1" "o/r --log x 1" "o/r 0"; do
  # shellcheck disable=SC2086
  scan $args
  assert_eq 2 "$RC" "exit status for '$args'"
  assert_contains "$ERR" "usage:" "message for '$args'"
done

# ---------------------------------------------------------------------------
t "API error"
reset
scan o/r 99
assert_eq 2 "$RC" "exit status"
assert_contains "$ERR" "repos/o/r/pulls/99" "names the call"
assert_contains "$ERR" "HTTP 404" "includes gh's error"
assert_eq "" "$OUT" "no output"

done_testing
