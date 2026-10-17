# agent-skills

Claude Code と Codex で共通に使うエージェントスキル集。

## スキル一覧

| スキル | 用途 |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | GitHub の issue を決まった書式（タスク用・不具合用）で起票する |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | issue を実装して PR を作り、CI 失敗やレビュー指摘に対応する（マージはしない） |
| [pr-review](skills/pr-review/SKILL.md) | PR を優先度付き（P0〜P3・Question）でレビューし、対応を確認してマージ可否を判定する（`--merge` 指定時はマージまで） |

各スキルは `skills/<name>/SKILL.md` に置く。

## Claude のプラグインとしての導入

このリポジトリは Claude のプラグインマーケットプレイス（`yasukei-agent-skills`）でもある。
リポジトリ全体が1つのプラグイン `agent-skills` で、スキルは `agent-skills:<スキル名>`（例: `agent-skills:issue-to-pr`）として使える。

`plugin.json` に `version` を書いていないので、バージョンはコミット SHA で決まり、`main` へのコミットごとに更新が配布される。

### Claude Code

```text
/plugin marketplace add yasukei/agent-skills
/plugin install agent-skills@yasukei-agent-skills
```

### claude.ai

claude.ai に登録すると、claude.ai のアカウントでサインインした Claude Code にも自動で同期される（`agent-skills@synced` として読み込まれる）。

1. claude.ai の Customize → Plugins → Add marketplace を開く
2. リポジトリの URL（`https://github.com/yasukei/agent-skills`）を入力する
3. Sync を押す

登録したら、以前 claude.ai に手で取り込んだスキルのコピー（`create-issue` など）は削除する。
残しておくと同じ description のスキルが2つ並び、古いほうが使われることがある。

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
- 各スキルへのシンボリックリンクを `.claude/skills/<name>` と `.agents/skills/<name>` に張る（`--codex-only` 指定時は `.agents/skills/<name>` だけ）
- 同名のリポジトリ固有スキル（実ディレクトリや、`.agent-skills` 以外へのリンク）がある場合は、上書きせず警告してスキップする
- 共有リポジトリから消えたスキルのリンクを削除する
- 変更をステージする（コミットはしない）

何度実行してもよいので、このリポジトリにスキルを追加・削除したときも再実行すればリンクが揃う。

### Claude 側をプラグインで導入する場合（`--codex-only`）

Claude 側は上の「Claude のプラグインとしての導入」で入れ、このスクリプトでは Codex 用のリンクだけを張る場合は `--codex-only` を付ける。

```bash
.agent-skills/scripts/setup.sh --codex-only
git commit -m "chore: link shared agent skills for Codex only"
```

- `.agents/skills/<name>` にだけリンクを張り、`.claude/skills/<name>` には張らない
- 以前このスクリプトが `.claude/skills` に張ったリンク（`.agent-skills/skills/` を指すもの）は削除する。リポジトリ固有のスキルには触れない
- `--update` と組み合わせられる（`setup.sh --update --codex-only`）

プラグインと `.claude/skills` のリンクを両方入れると、同じ description のスキルが2つ並ぶ。
submodule 側が古いままだと、修正前と修正後のどちらが使われるかが会話ごとに変わりうるため、どちらか一方にする。

`--codex-only` を付けずに再実行すると、`.claude/skills` のリンクも張り直される。

## 更新方針

submodule は常に `main` の最新を追う。`--update` を付けると、submodule を最新にしてからリンクを張り直す。

```bash
.agent-skills/scripts/setup.sh --update
git commit -m "chore: update shared agent skills"
```

## クラウド環境での設定

### Web 版 Claude Code とプラグイン

Web 版 Claude Code で、claude.ai から同期されたプラグイン（`agent-skills@synced`）が読み込まれるかどうかで、`setup.sh` の使い分けが変わる。

- 読み込まれる場合: `--codex-only` を推奨する。Claude 側はプラグインに一本化できる
- 読み込まれない場合: Web 版 Claude Code でも使うリポジトリでは、従来どおり `--codex-only` を付けずに両方にリンクを張る

確認結果: **未確認**（このリポジトリを claude.ai に登録したあとに確認して更新する）。
なお、Web 版 Claude Code のセッションでは、claude.ai に手で取り込んだスキルが `~/.claude/skills/synced/` に同期されて読み込まれること、
同期プラグイン用のディレクトリ `~/.claude/plugins/synced/` が作られることは確認済み。

### submodule の初期化

Codex Cloud や Web 版 Claude Code では submodule が自動で初期化されない場合があるため、
環境設定の setup script に次を入れる。`--remote` を付けると、記録済みのコミットではなく `main` の最新を取得する。

```bash
git submodule update --init --recursive --remote
```

`--remote` で取得した結果が記録済みのコミットより新しいと、`git status` で `.agent-skills` が変更ありと表示される。
意図せずコミットに混ざらないよう、submodule の更新は上の「更新方針」の手順で別コミットにする。
