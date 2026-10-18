#!/usr/bin/env bash
# scripts/validate-skills.py のテスト。
# 一時ディレクトリに正しいスキルを作り、1か所ずつ壊して検証が失敗し、問題の箇所が出力されることを確かめる。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/validate-skills.py"
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 正しいスキルを1つだけ持つ skills ディレクトリを $WORK/skills に作り直す。
# 引数は SKILL.md の frontmatter の中身（省略時は正しいもの）
make_skill() {
  local front="${1:-name: my-skill
description: テスト用のスキル。}"
  rm -rf "$WORK/skills"
  mkdir -p "$WORK/skills/my-skill/references" "$WORK/skills/my-skill/scripts" "$WORK/skills/my-skill/assets"
  cat >"$WORK/skills/my-skill/SKILL.md" <<EOF
---
$front
---

# my-skill

詳しくは \`references/guide.md\` を読む。テンプレートは [こちら](assets/template.md#usage)。
\`scripts/run.sh\` を実行する。外部の [仕様](https://agentskills.io/specification) と [見出し](#my-skill) は対象外。
EOF
  echo guide >"$WORK/skills/my-skill/references/guide.md"
  echo template >"$WORK/skills/my-skill/assets/template.md"
  printf '#!/bin/sh\n' >"$WORK/skills/my-skill/scripts/run.sh"
  chmod +x "$WORK/skills/my-skill/scripts/run.sh"
}

# 検証を実行し、OUT・ERR・RC に結果を入れる。引数は skills ディレクトリ（省略時は $WORK/skills）
run_validate() {
  RC=0
  "$SCRIPT" "${1:-$WORK/skills}" >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT="$(cat "$WORK/out")"
  ERR="$(cat "$WORK/err")"
}

# 検証が失敗し、標準エラーに期待する文字列が出ていることを確かめる
assert_fails_with() {
  assert_eq 1 "$RC" "終了コード"
  assert_contains "$ERR" "$1" "エラー出力"
}

# ---------------------------------------------------------------------------
t "このリポジトリのスキル"
run_validate "$ROOT/skills"
assert_eq 0 "$RC" "終了コード（$ERR）"
assert_contains "$OUT" "create-issue, issue-to-pr, pr-review" "検証したスキル"

# ---------------------------------------------------------------------------
t "正しいスキル"
make_skill
run_validate
assert_eq 0 "$RC" "終了コード（$ERR）"
assert_contains "$OUT" "1 skills ok: my-skill" "標準出力"

# ---------------------------------------------------------------------------
t "引数なしでリポジトリの skills/ を検証する"
RC=0
(cd "$WORK" && "$SCRIPT") >"$WORK/out" 2>"$WORK/err" || RC=$?
assert_eq 0 "$RC" "終了コード"
assert_contains "$(cat "$WORK/out")" "create-issue, issue-to-pr, pr-review" "検証したスキル"

# ---------------------------------------------------------------------------
t "name が引用符付き"
make_skill 'name: "my-skill"
description: テスト用のスキル。'
run_validate
assert_eq 0 "$RC" "終了コード（$ERR）"

# ---------------------------------------------------------------------------
t "description がない"
make_skill 'name: my-skill'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: ありません"

# ---------------------------------------------------------------------------
t "description が空"
make_skill 'name: my-skill
description: ""'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: 空です"

# ---------------------------------------------------------------------------
t "description が1024文字を超える"
make_skill "name: my-skill
description: $(printf 'a%.0s' $(seq 1025))"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: description: 1024文字を超えています（1025文字）"

# ---------------------------------------------------------------------------
t "name がない"
make_skill 'description: テスト用のスキル。'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: name: ありません"

# ---------------------------------------------------------------------------
t "name がディレクトリ名と一致しない"
make_skill 'name: other-skill
description: テスト用のスキル。'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: name: ディレクトリ名 'my-skill' と一致しません: 'other-skill'"

# ---------------------------------------------------------------------------
t "name の形式が不正"
for bad in My-Skill my_skill -my-skill my-skill- my--skill; do
  make_skill "name: \"$bad\"
description: テスト用のスキル。"
  run_validate
  assert_fails_with "name: 英小文字・数字・ハイフンだけで書き"
  assert_contains "$ERR" "'$bad'" "不正な name を表示する"
done

# ---------------------------------------------------------------------------
t "name が64文字を超える"
long="$(printf 'a%.0s' $(seq 65))"
make_skill "name: $long
description: テスト用のスキル。"
mv "$WORK/skills/my-skill" "$WORK/skills/$long"
run_validate
assert_fails_with "name: 64文字を超えています（65文字）"

# ---------------------------------------------------------------------------
t "frontmatter で始まっていない"
make_skill
sed -i '1d' "$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: '---' で囲んだ YAML の frontmatter で始まっていません"

# ---------------------------------------------------------------------------
t "frontmatter が YAML として解析できない"
make_skill 'name: [my-skill
description: テスト用のスキル。'
run_validate
assert_fails_with "skills/my-skill/SKILL.md: frontmatter を YAML として解析できません"

# ---------------------------------------------------------------------------
t "SKILL.md がない"
make_skill
mkdir "$WORK/skills/empty-skill"
run_validate
assert_fails_with "skills/empty-skill/SKILL.md: ありません"

# ---------------------------------------------------------------------------
t "references/ のファイルが存在しない"
make_skill
rm "$WORK/skills/my-skill/references/guide.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: 参照 references/guide.md: ファイルがありません"

# ---------------------------------------------------------------------------
t "日本語の直後にある参照も検証する"
make_skill
echo '詳細はreferences/missing.mdを読む。' >>"$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: 参照 references/missing.md: ファイルがありません"

# ---------------------------------------------------------------------------
t "Markdown のリンク先が存在しない"
make_skill
rm "$WORK/skills/my-skill/assets/template.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: 参照 assets/template.md: ファイルがありません"

# ---------------------------------------------------------------------------
t "リンク先がスキルのディレクトリの外"
make_skill
echo '[README](../../README.md)' >>"$WORK/skills/my-skill/SKILL.md"
run_validate
assert_fails_with "skills/my-skill/SKILL.md: 参照 ../../README.md: スキルのディレクトリの外を指しています"

# ---------------------------------------------------------------------------
t "scripts/ のファイルに実行権限がない"
make_skill
chmod -x "$WORK/skills/my-skill/scripts/run.sh"
run_validate
assert_fails_with "skills/my-skill/scripts/run.sh: 実行権限がありません"

# ---------------------------------------------------------------------------
t "問題が複数あればすべて出力する"
make_skill 'name: other-skill'
chmod -x "$WORK/skills/my-skill/scripts/run.sh"
run_validate
assert_fails_with "name: ディレクトリ名 'my-skill' と一致しません"
assert_contains "$ERR" "description: ありません" "description"
assert_contains "$ERR" "scripts/run.sh: 実行権限がありません" "実行権限"
assert_contains "$ERR" "3 件の問題があります" "件数"

# ---------------------------------------------------------------------------
t "不正な引数"
run_validate "$WORK/no-such-dir"
assert_fails_with "ディレクトリがありません"

done_testing
