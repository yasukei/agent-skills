#!/usr/bin/env bash
# scripts/setup.sh のテスト。
# 一時ディレクトリに共有リポジトリ役のローカル bare リポジトリと導入先リポジトリを作り、
# AGENT_SKILLS_URL で前者を指定して実行する。ネットワークには依存しない。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/scripts/setup.sh"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# git フックなどから実行されたときに、外側のリポジトリを操作しないようにする
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# 利用者の git 設定に影響されないよう、テスト専用の設定を使う。
# protocol.file.allow はローカルパスを submodule として追加するために必要
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

# 共有リポジトリ役の bare リポジトリを作る。引数はスキル名
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

# 共有リポジトリの main にスキルを追加する / 削除する
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

# 導入先リポジトリを作り、そこへ cd する
make_target() {
  TARGET="$WORK/target-$1"
  rm -rf "$TARGET"
  git init -q "$TARGET"
  cd "$TARGET" || exit 1
  echo target >README.md
  git add README.md
  git commit -qm init
}

# setup.sh を実行し、ERR・RC に結果を入れる
run_setup() {
  RC=0
  "$SETUP" "$@" >/dev/null 2>"$WORK/err" || RC=$?
  ERR="$(cat "$WORK/err")"
  if [ "$RC" -ne 0 ]; then
    echo "setup.sh $* が終了コード $RC で終了: $ERR" >&2
  fi
}

# パスがステージされているか（行単位で完全一致）
assert_staged() {
  if git diff --cached --name-only | grep -qxF "$1"; then pass; else fail "$1 がステージされていない"; fi
}

# パスの削除がステージされているか
assert_staged_deletion() {
  # 導入先の切り替えでは、同じリンク先のリンクが rename と判定されることがある。
  # ここでは元のパスの削除を確認するため、rename 検出を無効にする。
  if git diff --cached --no-renames --name-only --diff-filter=D | grep -qxF "$1"; then pass; else fail "$1 の削除がステージされていない"; fi
}

# ---------------------------------------------------------------------------
t "初回導入"
make_shared alpha beta
make_target initial
run_setup
assert_eq 0 "$RC" "終了コード"
assert_eq ".agent-skills" "$(git config -f .gitmodules --get submodule..agent-skills.path)" "submodule のパス"
for dir in .claude/skills .agents/skills; do
  for name in alpha beta; do
    assert_link "$dir/$name" "$L/$name"
    assert_staged "$dir/$name"
  done
done
assert_staged .gitmodules
assert_staged .agent-skills

# ---------------------------------------------------------------------------
t "再実行"
git commit -qm "add skills"
run_setup
assert_eq 0 "$RC" "終了コード"
assert_eq "" "$(git status --porcelain)" "2回目の実行で差分が出ない"

# ---------------------------------------------------------------------------
t "衝突（実ディレクトリ）"
make_shared alpha beta
make_target conflict-dir
mkdir -p .claude/skills/alpha
echo "# repo specific" >.claude/skills/alpha/SKILL.md
run_setup
assert_eq 0 "$RC" "終了コード"
assert_dir .claude/skills/alpha
assert_eq "# repo specific" "$(cat .claude/skills/alpha/SKILL.md)" "リポジトリ固有スキルの中身"
assert_contains "$ERR" "警告: .claude/skills/alpha は既に存在するためスキップします" "警告"
assert_link .claude/skills/beta "$L/beta"
assert_link .agents/skills/alpha "$L/alpha"

# ---------------------------------------------------------------------------
t "衝突（別の場所へのリンク）"
make_shared alpha beta
make_target conflict-link
# .agents/skills のリポジトリ固有スキルを .claude/skills からも参照している構成
mkdir -p .agents/skills/alpha .claude/skills
echo "# repo specific" >.agents/skills/alpha/SKILL.md
ln -s ../../.agents/skills/alpha .claude/skills/alpha
run_setup
assert_eq 0 "$RC" "終了コード"
assert_link .claude/skills/alpha ../../.agents/skills/alpha
assert_dir .agents/skills/alpha
assert_contains "$ERR" "警告: .claude/skills/alpha は既に存在するためスキップします" "警告"
assert_link .claude/skills/beta "$L/beta"

# ---------------------------------------------------------------------------
t "スキルの削除"
make_shared alpha beta
make_target remove
run_setup
git commit -qm "add skills"
shared_remove beta
run_setup --update
assert_eq 0 "$RC" "終了コード"
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
assert_eq 0 "$RC" "終了コード"
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

  t "$option で初回導入"
  make_shared alpha beta
  make_target "${option#--}-initial"
  run_setup "$option"
  assert_eq 0 "$RC" "終了コード"
  for name in alpha beta; do
    assert_link "$selected/$name" "$L/$name"
    assert_staged "$selected/$name"
    assert_missing "$excluded/$name"
  done
  assert_missing "$excluded"
  assert_staged .gitmodules
  assert_staged .agent-skills

  t "$option の再実行"
  git commit -qm "add skills"
  run_setup "$option" "$option"
  assert_eq 0 "$RC" "終了コード"
  assert_eq "" "$(git status --porcelain)" "再実行で差分が出ない"

  t "$option と --update の併用"
  shared_add gamma
  run_setup --update "$option"
  assert_eq 0 "$RC" "終了コード"
  assert_link "$selected/gamma" "$L/gamma"
  assert_staged "$selected/gamma"
  assert_staged .agent-skills
  assert_missing "$excluded"
  git commit -qm "update skills"

  t "$option から $opposite への切り替え"
  run_setup "$opposite"
  assert_eq 0 "$RC" "終了コード"
  for name in alpha beta gamma; do
    assert_missing "$selected/$name"
    assert_staged_deletion "$selected/$name"
    assert_link "$excluded/$name" "$L/$name"
    assert_staged "$excluded/$name"
  done
  git commit -qm "switch skills"

  t "片方のみの導入から指定なしに戻す"
  run_setup
  assert_eq 0 "$RC" "終了コード"
  for name in alpha beta gamma; do
    assert_link "$selected/$name" "$L/$name"
    assert_staged "$selected/$name"
    assert_link "$excluded/$name" "$L/$name"
  done
  git commit -qm "restore both"

  t "$option は共有リンクだけを削除し、リポジトリ固有のスキルを保持する"
  mkdir -p "$excluded/local"
  echo "# repo specific" >"$excluded/local/SKILL.md"
  ln -s ../../missing-local-skill "$excluded/foreign"
  git add "$excluded/local" "$excluded/foreign"
  git commit -qm "add local skills"
  shared_remove beta
  # option を先に指定する順序でも --update と併用できる
  run_setup "$option" --update
  assert_eq 0 "$RC" "終了コード"
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
  assert_eq "# repo specific" "$(cat "$excluded/local/SKILL.md")" "固有スキルの中身"
  assert_link "$excluded/foreign" ../../missing-local-skill
  assert_eq "" "$(git diff --cached --name-only -- "$excluded/local" "$excluded/foreign")" "固有スキルは変更しない"
done

# ---------------------------------------------------------------------------
t "--codex-only と --claude-only の同時指定は順序によらず拒否する"
make_target conflicting-options
for first in --codex-only --claude-only; do
  if [ "$first" = --codex-only ]; then second=--claude-only; else second=--codex-only; fi
  run_setup --update "$first" "$second" 2>/dev/null
  assert_eq 1 "$RC" "終了コード"
  assert_contains "$ERR" "同時に指定できません" "競合するオプションの説明"
  assert_missing .gitmodules
  assert_missing .agent-skills
  assert_missing .claude
  assert_missing .agents
  assert_eq "" "$(git status --porcelain)" "引数エラー時は何も変更しない"
done

t "導入済みでも同時指定はリンクや submodule を変更しない"
make_shared alpha
run_setup
git commit -qm "add skills"
shared_add gamma
run_setup --claude-only --update --codex-only 2>/dev/null
assert_eq 1 "$RC" "終了コード"
assert_contains "$ERR" "同時に指定できません" "競合するオプションの説明"
assert_eq "" "$(git status --porcelain)" "更新やリンク削除より前に引数エラーにする"
for dir in .claude/skills .agents/skills; do
  assert_link "$dir/alpha" "$L/alpha"
  assert_missing "$dir/gamma"
done

# ---------------------------------------------------------------------------
t "不正な引数"
make_target bad-arg
run_setup --unknown 2>/dev/null
assert_eq 1 "$RC" "終了コード"
assert_contains "$ERR" "usage:" "使い方を表示する"
assert_missing .gitmodules

done_testing
