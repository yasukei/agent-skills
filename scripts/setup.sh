#!/usr/bin/env bash
# Add agent-skills as a submodule and create per-skill symbolic links in
# .claude/skills and .agents/skills. Safe to run any number of times.
# Usage (run inside the target repository):
#   First time:  curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash
#   After that:  .agent-skills/scripts/setup.sh [--update] [--codex-only | --claude-only]
#     --update      update the submodule to the latest main, then recreate the links
#     --codex-only  link only into .agents/skills (when Claude gets the skills from the plugin).
#                   Removes links this script created earlier in .claude/skills
#     --claude-only link only into .claude/skills (when Codex gets the skills from the plugin).
#                   Removes links this script created earlier in .agents/skills
#     --codex-only and --claude-only cannot be used together.
# Changes are only staged, never committed.
set -euo pipefail

URL="${AGENT_SKILLS_URL:-https://github.com/yasukei/agent-skills.git}"
SUBMODULE="${AGENT_SKILLS_PATH:-.agent-skills}"
LINK_DIRS=(.claude/skills .agents/skills)
# Directories where no links are created and links this script created are removed
UNLINK_DIRS=()

UPDATE=0
CODEX_ONLY=0
CLAUDE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    --codex-only) CODEX_ONLY=1 ;;
    --claude-only) CLAUDE_ONLY=1 ;;
    *) echo "usage: $0 [--update] [--codex-only | --claude-only]" >&2; exit 1 ;;
  esac
done

if [ "$CODEX_ONLY" -eq 1 ] && [ "$CLAUDE_ONLY" -eq 1 ]; then
  echo "--codex-only and --claude-only cannot be used together" >&2
  exit 1
fi
if [ "$CODEX_ONLY" -eq 1 ]; then
  LINK_DIRS=(.agents/skills)
  UNLINK_DIRS=(.claude/skills)
elif [ "$CLAUDE_ONLY" -eq 1 ]; then
  LINK_DIRS=(.claude/skills)
  UNLINK_DIRS=(.agents/skills)
fi

cd "$(git rev-parse --show-toplevel)"

# Add and initialize the submodule
if ! git config -f .gitmodules --get "submodule.$SUBMODULE.path" >/dev/null 2>&1; then
  echo "Adding submodule: $SUBMODULE"
  git submodule add -b main "$URL" "$SUBMODULE"
elif [ ! -d "$SUBMODULE/skills" ]; then
  git submodule update --init "$SUBMODULE"
fi

if [ "$UPDATE" -eq 1 ]; then
  git submodule update --remote "$SUBMODULE"
fi

# Links live at <dir>/<name>, so go up two levels to the repository root
PREFIX="../../$SUBMODULE/skills"
STAGE=(.gitmodules "$SUBMODULE")

# ${arr[@]+...} keeps bash 3.2 with set -u from failing on an empty array
for dir in ${UNLINK_DIRS[@]+"${UNLINK_DIRS[@]}"}; do
  # Remove only links this script created; never touch the repository's own skills
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$PREFIX"/*)
        echo "Removed: $link"
        rm "$link"
        git rm -q --cached --ignore-unmatch "$link"
        ;;
    esac
  done
done

for dir in "${LINK_DIRS[@]}"; do
  mkdir -p "$dir"

  # Remove links to skills that are gone from the shared skills
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$PREFIX"/*)
        if [ ! -e "$link" ]; then
          echo "Removed: $link (target does not exist)"
          rm "$link"
          git rm -q --cached --ignore-unmatch "$link"
        fi
        ;;
    esac
  done

  for skill in "$SUBMODULE"/skills/*/; do
    name="$(basename "$skill")"
    dest="$dir/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      # Only links this script created may be recreated.
      # Never overwrite the repository's own skills (real directories or links elsewhere)
      case "$(readlink "$dest" 2>/dev/null)" in
        "$PREFIX/$name") ;;
        *)
          echo "Warning: $dest already exists, skipping" >&2
          continue
          ;;
      esac
    fi
    ln -sfn "$PREFIX/$name" "$dest"
    STAGE+=("$dest")
  done
done

# Stage only the links this script created, so the repository's own skills are left alone
git add "${STAGE[@]}"
echo "Done. Check with git status before committing."
