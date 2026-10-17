# agent-skills

Claude Code と Codex で共通に使うエージェントスキル集。

## スキル一覧

| スキル | 用途 |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | GitHub の issue を決まった書式（タスク用・不具合用）で起票する |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | issue を実装して PR を作り、CI 失敗やレビュー指摘に対応する（マージはしない） |
| [pr-review-and-merge](skills/pr-review-and-merge/SKILL.md) | PR を優先度付き（P0〜P3・Question）でレビューし、対応を確認してマージする |

各スキルは `skills/<name>/SKILL.md` に置く。

## 各リポジトリへの導入

submodule として追加し、`.claude/skills/` と `.agents/skills/` からスキル単位でシンボリックリンクを張る。
スキル単位にしておくと、そのリポジトリ固有のスキルも同じディレクトリに共存させられる。

```bash
# main ブランチを追跡する submodule として追加
git submodule add -b main https://github.com/yasukei/agent-skills.git .agent-skills

# スキル単位でシンボリックリンクを張る（Claude Code 用と Codex 用）
mkdir -p .claude/skills .agents/skills
for s in .agent-skills/skills/*/; do
  name=$(basename "$s")
  ln -sfn "../../.agent-skills/skills/$name" ".claude/skills/$name"
  ln -sfn "../../.agent-skills/skills/$name" ".agents/skills/$name"
done

git add .gitmodules .agent-skills .claude/skills .agents/skills
git commit -m "chore: add shared agent skills"
```

このリポジトリにスキルを追加したときは、上の `for` ループを再実行してリンクを張り直す。

## 更新方針

submodule は常に `main` の最新を追う。

```bash
git submodule update --remote .agent-skills
git add .agent-skills
git commit -m "chore: update shared agent skills"
```

## クラウド環境での設定

Codex Cloud や Web 版 Claude Code では submodule が自動で初期化されない場合があるため、
環境設定の setup script に次を入れる。`--remote` を付けると、記録済みのコミットではなく `main` の最新を取得する。

```bash
git submodule update --init --recursive --remote
```

`--remote` で取得した結果が記録済みのコミットより新しいと、`git status` で `.agent-skills` が変更ありと表示される。
意図せずコミットに混ざらないよう、submodule の更新は上の「更新方針」の手順で別コミットにする。
