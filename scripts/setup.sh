#!/usr/bin/env bash
# agent-skills を submodule として導入し、.claude/skills と .agents/skills に
# スキル単位のシンボリックリンクを張る。何度実行してもよい。
# 使い方（導入先リポジトリの中で実行する）:
#   初回:   curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash
#   2回目以降: .agent-skills/scripts/setup.sh [--update] [--codex-only | --claude-only]
#     --update      submodule を main の最新に更新してからリンクを張り直す
#     --codex-only  .agents/skills にだけリンクを張る（Claude 側はプラグインで導入する場合）。
#                   以前このスクリプトが .claude/skills に張ったリンクは削除する
#     --claude-only .claude/skills にだけリンクを張る（Codex 側はプラグインで導入する場合）。
#                   以前このスクリプトが .agents/skills に張ったリンクは削除する
#     --codex-only と --claude-only は同時に指定できない。
# 変更はステージするだけで、コミットはしない。
set -euo pipefail

URL="${AGENT_SKILLS_URL:-https://github.com/yasukei/agent-skills.git}"
SUBMODULE="${AGENT_SKILLS_PATH:-.agent-skills}"
LINK_DIRS=(.claude/skills .agents/skills)
# リンクを張らず、このスクリプトが張ったリンクを削除するディレクトリ
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
  echo "--codex-only と --claude-only は同時に指定できません" >&2
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

# submodule の追加・初期化
if ! git config -f .gitmodules --get "submodule.$SUBMODULE.path" >/dev/null 2>&1; then
  echo "submodule を追加します: $SUBMODULE"
  git submodule add -b main "$URL" "$SUBMODULE"
elif [ ! -d "$SUBMODULE/skills" ]; then
  git submodule update --init "$SUBMODULE"
fi

if [ "$UPDATE" -eq 1 ]; then
  git submodule update --remote "$SUBMODULE"
fi

# リンクは <dir>/<name> に置くので、リポジトリルートまで2階層上がる
PREFIX="../../$SUBMODULE/skills"
STAGE=(.gitmodules "$SUBMODULE")

# ${arr[@]+...} は bash 3.2 で空配列を set -u で参照してもエラーにしないため
for dir in ${UNLINK_DIRS[@]+"${UNLINK_DIRS[@]}"}; do
  # このスクリプトが張ったリンクだけを削除し、リポジトリ固有のスキルには触れない
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$PREFIX"/*)
        echo "削除: $link"
        rm "$link"
        git rm -q --cached --ignore-unmatch "$link"
        ;;
    esac
  done
done

for dir in "${LINK_DIRS[@]}"; do
  mkdir -p "$dir"

  # 共有スキルから消えたスキルのリンクを削除する
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$PREFIX"/*)
        if [ ! -e "$link" ]; then
          echo "削除: $link（リンク先がありません）"
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
      # 張り直してよいのはこのスクリプトが張ったリンクだけ。
      # リポジトリ固有のスキル（実ディレクトリや別の場所へのリンク）は上書きしない
      case "$(readlink "$dest" 2>/dev/null)" in
        "$PREFIX/$name") ;;
        *)
          echo "警告: $dest は既に存在するためスキップします" >&2
          continue
          ;;
      esac
    fi
    ln -sfn "$PREFIX/$name" "$dest"
    STAGE+=("$dest")
  done
done

# リポジトリ固有のスキルは巻き込まないよう、このスクリプトが張ったリンクだけをステージする
git add "${STAGE[@]}"
echo "完了しました。git status で確認してからコミットしてください。"
