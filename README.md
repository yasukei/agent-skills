# agent-skills

Claude Code と Codex で共通に使うエージェントスキル集。

## スキル一覧

| スキル | 用途 |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | GitHub の issue を決まった書式（タスク用・不具合用）で起票する |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | issue を実装して PR を作り、CI 失敗やレビュー指摘に対応する（マージはしない） |
| [pr-review](skills/pr-review/SKILL.md) | PR を優先度付き（P0〜P3・Question）でレビューし、対応を確認してマージ可否を判定する（`--merge` 指定時はマージまで） |

各スキルは `skills/<name>/SKILL.md` に置く。

## 各リポジトリへの導入

submodule として追加し、`.claude/skills/` と `.agents/skills/` からスキル単位でシンボリックリンクを張る。
スキル単位にしておくと、そのリポジトリ固有のスキルも同じディレクトリに共存させられる。

導入先リポジトリの中で [scripts/setup.sh](scripts/setup.sh) を実行する。

```bash
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash
git commit -m "chore: add shared agent skills"
```

スクリプトがやること：

- `main` ブランチを追跡する submodule として `.agent-skills` に追加する（追加済みならスキップ）
- 各スキルへのシンボリックリンクを `.claude/skills/<name>` と `.agents/skills/<name>` に張る
- 同名のリポジトリ固有スキル（実ディレクトリや、`.agent-skills` 以外へのリンク）がある場合は、上書きせず警告してスキップする
- 共有リポジトリから消えたスキルのリンクを削除する
- 変更をステージする（コミットはしない）

何度実行してもよいので、このリポジトリにスキルを追加・削除したときも再実行すればリンクが揃う。

## 更新方針

submodule は常に `main` の最新を追う。`--update` を付けると、submodule を最新にしてからリンクを張り直す。

```bash
.agent-skills/scripts/setup.sh --update
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
