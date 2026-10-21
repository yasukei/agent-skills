#!/usr/bin/env bash
# Tests for scripts/setup.sh.
# Create, in a temporary directory, a local bare repository acting as the shared repository and a target repository,
# and run setup.sh with AGENT_SKILLS_URL pointing to the former. Does not depend on the network.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/scripts/setup.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Do not operate on an outer repository when run from a git hook, etc.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# Use test-only git configuration so the user's git settings do not interfere.
# protocol.file.allow is needed to add a local path as a submodule
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main
git config --global protocol.file.allow always
git config --global advice.detachedHead false

SHARED="$WORK/shared.git"
export AGENT_SKILLS_URL="$SHARED"

L='../../.agent-skills/skills'

# Create the bare repository acting as the shared repository. Arguments are skill names
make_shared() {
  rm -rf "$SHARED" "$WORK/shared-src"
  git init -q --bare "$SHARED"
  git clone -q "$SHARED" "$WORK/shared-src" 2>/dev/null
  for name in "$@"; do
    mkdir -p "$WORK/shared-src/skills/$name"
    echo "# $name" >"$WORK/shared-src/skills/$name/SKILL.md"
  done
  git -C "$WORK/shared-src" add -A
  git -C "$WORK/shared-src" commit -qm init
  git -C "$WORK/shared-src" push -q origin main
}

# Add / remove a skill on the shared repository's main
shared_add() {
  mkdir -p "$WORK/shared-src/skills/$1"
  echo "# $1" >"$WORK/shared-src/skills/$1/SKILL.md"
  git -C "$WORK/shared-src" add -A
  git -C "$WORK/shared-src" commit -qm "add $1"
  git -C "$WORK/shared-src" push -q origin main
}
shared_remove() {
  git -C "$WORK/shared-src" rm -rq "skills/$1"
  git -C "$WORK/shared-src" commit -qm "remove $1"
  git -C "$WORK/shared-src" push -q origin main
}

# Create the target repository and cd into it
make_target() {
  TARGET="$WORK/target-$1"
  rm -rf "$TARGET"
  git init -q "$TARGET"
  cd "$TARGET" || exit 1
  echo target >README.md
  git add README.md
  git commit -qm init
}

# Run setup.sh and store the results in ERR and RC
run_setup() {
  RC=0
  "$SETUP" "$@" >/dev/null 2>"$WORK/err" || RC=$?
  ERR="$(cat "$WORK/err")"
  if [ "$RC" -ne 0 ]; then
    echo "setup.sh $* exited with status $RC: $ERR" >&2
  fi
}

# Whether a path is staged (exact line match)
assert_staged() {
  if git diff --cached --name-only | grep -qxF "$1"; then pass; else fail "$1 is not staged"; fi
}

# Whether the deletion of a path is staged
assert_staged_deletion() {
  # When switching targets, a link with the same target may be detected as a rename.
  # This checks the deletion of the original path, so disable rename detection.
  if git diff --cached --no-renames --name-only --diff-filter=D | grep -qxF "$1"; then pass; else fail "deletion of $1 is not staged"; fi
}

# ---------------------------------------------------------------------------
t "first install"
make_shared alpha beta
make_target initial
run_setup
assert_eq 0 "$RC" "exit status"
assert_eq ".agent-skills" "$(git config -f .gitmodules --get submodule..agent-skills.path)" "submodule path"
for dir in .claude/skills .agents/skills; do
  for name in alpha beta; do
    assert_link "$dir/$name" "$L/$name"
    assert_staged "$dir/$name"
  done
done
assert_staged .gitmodules
assert_staged .agent-skills

# ---------------------------------------------------------------------------
t "rerun"
git commit -qm "add skills"
run_setup
assert_eq 0 "$RC" "exit status"
assert_eq "" "$(git status --porcelain)" "second run makes no changes"

# ---------------------------------------------------------------------------
t "conflict (real directory)"
make_shared alpha beta
make_target conflict-dir
mkdir -p .claude/skills/alpha
echo "# repo specific" >.claude/skills/alpha/SKILL.md
run_setup
assert_eq 0 "$RC" "exit status"
assert_dir .claude/skills/alpha
assert_eq "# repo specific" "$(cat .claude/skills/alpha/SKILL.md)" "content of the repository's own skill"
assert_contains "$ERR" "Warning: .claude/skills/alpha already exists, skipping" "warning"
assert_link .claude/skills/beta "$L/beta"
assert_link .agents/skills/alpha "$L/alpha"

# ---------------------------------------------------------------------------
t "conflict (link elsewhere)"
make_shared alpha beta
make_target conflict-link
# A setup where .claude/skills also refers to a repository-specific skill in .agents/skills
mkdir -p .agents/skills/alpha .claude/skills
echo "# repo specific" >.agents/skills/alpha/SKILL.md
ln -s ../../.agents/skills/alpha .claude/skills/alpha
run_setup
assert_eq 0 "$RC" "exit status"
assert_link .claude/skills/alpha ../../.agents/skills/alpha
assert_dir .agents/skills/alpha
assert_contains "$ERR" "Warning: .claude/skills/alpha already exists, skipping" "warning"
assert_link .claude/skills/beta "$L/beta"

# ---------------------------------------------------------------------------
t "skill removal"
make_shared alpha beta
make_target remove
run_setup
git commit -qm "add skills"
shared_remove beta
run_setup --update
assert_eq 0 "$RC" "exit status"
for dir in .claude/skills .agents/skills; do
  assert_missing "$dir/beta"
  assert_staged_deletion "$dir/beta"
  assert_link "$dir/alpha" "$L/alpha"
done

# ---------------------------------------------------------------------------
t "--update"
make_shared alpha
make_target update
run_setup
git commit -qm "add skills"
shared_add gamma
run_setup --update
assert_eq 0 "$RC" "exit status"
for dir in .claude/skills .agents/skills; do
  assert_link "$dir/gamma" "$L/gamma"
  assert_staged "$dir/gamma"
done

# ---------------------------------------------------------------------------
for option in --codex-only --claude-only; do
  if [ "$option" = --codex-only ]; then
    selected=.agents/skills
    excluded=.claude/skills
    opposite=--claude-only
  else
    selected=.claude/skills
    excluded=.agents/skills
    opposite=--codex-only
  fi

  t "first install with $option"
  make_shared alpha beta
  make_target "${option#--}-initial"
  run_setup "$option"
  assert_eq 0 "$RC" "exit status"
  for name in alpha beta; do
    assert_link "$selected/$name" "$L/$name"
    assert_staged "$selected/$name"
    assert_missing "$excluded/$name"
  done
  assert_missing "$excluded"
  assert_staged .gitmodules
  assert_staged .agent-skills

  t "rerun with $option"
  git commit -qm "add skills"
  run_setup "$option" "$option"
  assert_eq 0 "$RC" "exit status"
  assert_eq "" "$(git status --porcelain)" "rerun makes no changes"

  t "$option with --update"
  shared_add gamma
  run_setup --update "$option"
  assert_eq 0 "$RC" "exit status"
  assert_link "$selected/gamma" "$L/gamma"
  assert_staged "$selected/gamma"
  assert_staged .agent-skills
  assert_missing "$excluded"
  git commit -qm "update skills"

  t "switch from $option to $opposite"
  run_setup "$opposite"
  assert_eq 0 "$RC" "exit status"
  for name in alpha beta gamma; do
    assert_missing "$selected/$name"
    assert_staged_deletion "$selected/$name"
    assert_link "$excluded/$name" "$L/$name"
    assert_staged "$excluded/$name"
  done
  git commit -qm "switch skills"

  t "switch from one side only back to no option"
  run_setup
  assert_eq 0 "$RC" "exit status"
  for name in alpha beta gamma; do
    assert_link "$selected/$name" "$L/$name"
    assert_staged "$selected/$name"
    assert_link "$excluded/$name" "$L/$name"
  done
  git commit -qm "restore both"

  t "$option removes only shared links and keeps the repository's own skills"
  mkdir -p "$excluded/local"
  echo "# repo specific" >"$excluded/local/SKILL.md"
  ln -s ../../missing-local-skill "$excluded/foreign"
  git add "$excluded/local" "$excluded/foreign"
  git commit -qm "add local skills"
  shared_remove beta
  # --update also works when the option comes first
  run_setup "$option" --update
  assert_eq 0 "$RC" "exit status"
  for name in alpha beta gamma; do
    assert_missing "$excluded/$name"
    assert_staged_deletion "$excluded/$name"
  done
  for name in alpha gamma; do
    assert_link "$selected/$name" "$L/$name"
  done
  assert_missing "$selected/beta"
  assert_staged_deletion "$selected/beta"
  assert_dir "$excluded/local"
  assert_eq "# repo specific" "$(cat "$excluded/local/SKILL.md")" "content of the repository's own skill"
  assert_link "$excluded/foreign" ../../missing-local-skill
  assert_eq "" "$(git diff --cached --name-only -- "$excluded/local" "$excluded/foreign")" "the repository's own skills are not changed"
done

# ---------------------------------------------------------------------------
t "--codex-only and --claude-only together are rejected in either order"
make_target conflicting-options
for first in --codex-only --claude-only; do
  if [ "$first" = --codex-only ]; then second=--claude-only; else second=--codex-only; fi
  run_setup --update "$first" "$second" 2>/dev/null
  assert_eq 1 "$RC" "exit status"
  assert_contains "$ERR" "cannot be used together" "explains the conflicting options"
  assert_missing .gitmodules
  assert_missing .agent-skills
  assert_missing .claude
  assert_missing .agents
  assert_eq "" "$(git status --porcelain)" "nothing changes on an argument error"
done

t "using both options after install changes neither links nor the submodule"
make_shared alpha
run_setup
git commit -qm "add skills"
shared_add gamma
run_setup --claude-only --update --codex-only 2>/dev/null
assert_eq 1 "$RC" "exit status"
assert_contains "$ERR" "cannot be used together" "explains the conflicting options"
assert_eq "" "$(git status --porcelain)" "the argument error comes before updating or removing links"
for dir in .claude/skills .agents/skills; do
  assert_link "$dir/alpha" "$L/alpha"
  assert_missing "$dir/gamma"
done

# ---------------------------------------------------------------------------
t "invalid argument"
make_target bad-arg
run_setup --unknown 2>/dev/null
assert_eq 1 "$RC" "exit status"
assert_contains "$ERR" "usage:" "prints usage"
assert_missing .gitmodules

done_testing
