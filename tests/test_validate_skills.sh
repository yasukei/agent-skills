#!/usr/bin/env bash
# Tests for scripts/validate-skills.py.
# Create a valid skill in a temporary directory, break one thing at a time, and check that validation fails and reports where.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/validate-skills.py"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Recreate $WORK/skills as a skills directory with a single valid skill.
# The argument is the content of the SKILL.md frontmatter (default: a valid one)
make_skill() {
  local front="${1:-name: my-skill
description: A skill for tests.}"
  rm -rf "$WORK/skills"
  mkdir -p "$WORK/skills/my-skill/references" "$WORK/skills/my-skill/scripts" "$WORK/skills/my-skill/assets"
  cat >"$WORK/skills/my-skill/SKILL.md" <<EOF
---
$front
---

# my-skill

See \`references/guide.md\`. The template is [here](assets/template.md#usage).
Run \`scripts/run.sh\`. The external [spec](https://agentskills.io/specification) and the [heading](#my-skill) are not checked.
EOF
  echo guide >"$WORK/skills/my-skill/references/guide.md"
  echo template >"$WORK/skills/my-skill/assets/template.md"
  printf '#!/bin/sh\n' >"$WORK/skills/my-skill/scripts/run.sh"
  chmod +x "$WORK/skills/my-skill/scripts/run.sh"
}

# Run the validation and store the results in OUT, ERR and RC. The argument is the skills directory (default $WORK/skills)
run_validate() {
  RC=0
  "$SCRIPT" "${1:-$WORK/skills}" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# Check that validation fails and stderr contains the expected string
assert_fails_with() {
  assert_eq 1 "$RC" "exit status"
  assert_contains "$ERR" "$1" "stderr"
}

# ---------------------------------------------------------------------------
t "this repository's skills"
run_validate "$ROOT/skills"
assert_eq 0 "$RC" "exit status ($ERR)"
assert_contains "$OUT" "create-issue, issue-to-pr, pr-review" "validated skills"

# ---------------------------------------------------------------------------
t "valid skill"
make_skill
run_validate
assert_eq 0 "$RC" "exit status ($ERR)"
assert_contains "$OUT" "1 skills ok: my-skill" "stdout"

# ---------------------------------------------------------------------------
t "validates the repository's skills/ when given no argument"
RC=0
(cd "$WORK" && "$SCRIPT") >"$WORK/out" 2>"$WORK/err" || RC=$?
assert_eq 0 "$RC" "exit status"
assert_contains "$(cat "$WORK/out")" "create-issue, issue-to-pr, pr-review" "validated skills"

# ---------------------------------------------------------------------------
t "name is quoted"
make_skill 'name: "my-skill"
description: A skill for tests.'
run_validate
assert_eq 0 "$RC" "exit status ($ERR)"

# ---------------------------------------------------------------------------
t "description is missing"
make_skill 'name: my-skill'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: missing"

# ---------------------------------------------------------------------------
t "description is empty"
make_skill 'name: my-skill
description: ""'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: empty"

# ---------------------------------------------------------------------------
t "description is longer than 1024 characters"
make_skill "name: my-skill
description: $(printf 'a%.0s' $(seq 1025))"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: longer than 1024 characters (1025)"

# ---------------------------------------------------------------------------
t "name is missing"
make_skill 'description: A skill for tests.'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: name: missing"

# ---------------------------------------------------------------------------
t "name does not match the directory name"
make_skill 'name: other-skill
description: A skill for tests.'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: name: does not match the directory name 'my-skill': 'other-skill'"

# ---------------------------------------------------------------------------
t "name has an invalid format"
for bad in My-Skill my_skill -my-skill my-skill- my--skill; do
  make_skill "name: \"$bad\"
description: A skill for tests."
  run_validate
  assert_fails_with "name: use only lowercase letters, digits and hyphens"
  assert_contains "$ERR" "'$bad'" "shows the invalid name"
done

# ---------------------------------------------------------------------------
t "name is longer than 64 characters"
long="$(printf 'a%.0s' $(seq 65))"
make_skill "name: $long
description: A skill for tests."
mv "$WORK/skills/my-skill" "$WORK/skills/$long"
run_validate
assert_fails_with "name: longer than 64 characters (65)"

# ---------------------------------------------------------------------------
t "does not start with a frontmatter"
make_skill
sed -i '1d' "$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: does not start with a YAML frontmatter enclosed in '---'"

# ---------------------------------------------------------------------------
t "frontmatter cannot be parsed as YAML"
make_skill 'name: [my-skill
description: A skill for tests.'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: cannot parse the frontmatter as YAML"

# ---------------------------------------------------------------------------
t "SKILL.md is missing"
make_skill
mkdir "$WORK/skills/empty-skill"
run_validate
assert_fails_with "skills/empty-skill/SKILL.md: not found"

# ---------------------------------------------------------------------------
t "file under references/ does not exist"
make_skill
rm "$WORK/skills/my-skill/references/guide.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: reference references/guide.md: file not found"

# ---------------------------------------------------------------------------
t "checks a reference right after Japanese text"
make_skill
# Japanese text ("see references/missing.md") written as UTF-8 escapes, so the source stays ASCII
printf '\xe8\xa9\xb3\xe7\xb4\xb0\xe3\x81\xafreferences/missing.md\xe3\x82\x92\xe8\xaa\xad\xe3\x82\x80\xe3\x80\x82\n' >>"$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: reference references/missing.md: file not found"

# ---------------------------------------------------------------------------
t "Markdown link target does not exist"
make_skill
rm "$WORK/skills/my-skill/assets/template.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: reference assets/template.md: file not found"

# ---------------------------------------------------------------------------
t "link target is outside the skill directory"
make_skill
echo '[README](../../README.md)' >>"$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: reference ../../README.md: points outside the skill directory"

# ---------------------------------------------------------------------------
t "file under scripts/ is not executable"
make_skill
chmod -x "$WORK/skills/my-skill/scripts/run.sh"
run_validate
assert_fails_with "skills/my-skill/scripts/run.sh: not executable"

# ---------------------------------------------------------------------------
t "reports every problem when there are several"
make_skill 'name: other-skill'
chmod -x "$WORK/skills/my-skill/scripts/run.sh"
run_validate
assert_fails_with "name: does not match the directory name 'my-skill'"
assert_contains "$ERR" "description: missing" "description"
assert_contains "$ERR" "scripts/run.sh: not executable" "executable bit"
assert_contains "$ERR" "3 problem(s) found" "count"

# ---------------------------------------------------------------------------
t "invalid argument"
run_validate "$WORK/no-such-dir"
assert_fails_with "directory not found"

done_testing
