# agent-skills

Claude Code・ChatGPT・Codex で共通に使うエージェントスキル集。

## スキル一覧

| スキル | 用途 |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | GitHub の issue を決まった書式（タスク用・不具合用）で起票する |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | issue を実装して PR を作り、CI 失敗やレビュー指摘に対応する（マージはしない） |
| [pr-review](skills/pr-review/SKILL.md) | PR を優先度付き（P0〜P3・Question）でレビューし、対応を確認してマージ可否を判定する（`--merge` 指定時はマージまで） |

各スキルは `skills/<name>/SKILL.md` に置く。

## 導入手順

### 導入手順 （Claude / Claude Code のプラグインとして）

このリポジトリは Claude のプラグインマーケットプレイス（`yasukei-agent-skills`）でもある。
リポジトリ全体が1つのプラグイン `agent-skills` で、スキルは `agent-skills:<スキル名>`（例: `agent-skills:issue-to-pr`）として使える。

`.claude-plugin/plugin.json` に `version` を書いていないので、バージョンはコミット SHA で決まり、`main` へのコミットごとに更新が配布される。

#### Claude Code

```text
/plugin marketplace add yasukei/agent-skills
/plugin install agent-skills@yasukei-agent-skills
```

#### claude.ai

claude.ai に登録すると、claude.ai のアカウントでサインインした Claude Code（CLI・Web 版）にも自動で同期され、`agent-skills@synced` として読み込まれる。
Web 版 Claude Code での確認結果は「[Web 版 Claude Code とプラグイン](#web-版-claude-code-とプラグイン)」を参照。

1. claude.ai の Customize → Plugins → Add marketplace を開く
2. リポジトリの URL（`https://github.com/yasukei/agent-skills`）を入力する
3. Sync を押す

登録したら、以前 claude.ai に手で取り込んだスキルのコピー（`create-issue` など）は削除する。
残しておくと同じ description のスキルが2つ並び、古いほうが使われることがある。

### 導入手順 （ChatGPT / Codex のプラグインとして）

ルートの [plugin.json](plugin.json) は Agent Plugins 1.0 形式のプラグイン定義、
[.agents/plugins/marketplace.json](.agents/plugins/marketplace.json) は配布カタログ。
リポジトリ全体を1つのプラグイン `agent-skills` として登録し、Claude 用と同じ `skills/` の3つのスキルを配布する。
`version` は省略している（[公式スキーマ](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)では任意）。

#### Codex にマーケットプレイスを登録する

```bash
codex plugin marketplace add yasukei/agent-skills
```

登録後、ChatGPT デスクトップアプリのプラグイン一覧で `Yasukei Agent Skills` をソースとして選び、`agent-skills` をインストールする。
詳しくは[公式のパッケージ化・ローカル導入手順](https://developers.openai.com/plugins/build/plugins)を参照。

#### Codex のプラグインを更新する

導入済みのプラグインを最新に更新するには、次を実行する。

```bash
codex plugin marketplace upgrade yasukei-agent-skills
```

#### ChatGPT のワークスペースに取り込む

ワークスペース管理者が Admin → Plugins → Add → Import marketplace を開き、次を指定する。

- Source: `https://github.com/yasukei/agent-skills`
- Path: 空欄（リポジトリルート）
- Branch, tag, or commit: `main`

取り込み後にプラグインのインストールポリシーを設定する。更新は日次同期、または `Sync now` で取り込む。
詳しくは[公式のインポート・同期手順](https://help.openai.com/en/articles/20001504-importing-and-syncing-plugin-marketplaces-from-github)を参照。

スキルの実行には、作業対象のリポジトリを操作できる環境と `git`・`gh` などのコマンド、GitHub の認証が必要。
プラグインを導入した環境では、同じスキルを `.agents/skills/` にも置くと重複するため、導入方法はどちらか一方にする。

### 導入手順 （git submodule として）

Claude / Codex の両方をプラグインで導入する場合、この手順は不要。
submodule として追加し、`.claude/skills/` と `.agents/skills/` からスキル単位でシンボリックリンクを張る。
スキル単位にしておくと、そのリポジトリ固有のスキルも同じディレクトリに共存させられる。

導入先リポジトリの中で [scripts/setup.sh](scripts/setup.sh) を実行する。

```bash
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash
git commit -m "chore: add shared agent skills"
```

スクリプトがやること：

- `main` ブランチを追跡する submodule として `.agent-skills` に追加する（追加済みならスキップ）
- 各スキルへのシンボリックリンクを `.claude/skills/<name>` と `.agents/skills/<name>` に張る（オプションで片方だけにできる）
- 同名のリポジトリ固有スキル（実ディレクトリや、`.agent-skills` 以外へのリンク）がある場合は、上書きせず警告してスキップする
- 共有リポジトリから消えたスキルのリンクを削除する
- 変更をステージする（コミットはしない）

何度実行してもよいので、このリポジトリにスキルを追加・削除したときも再実行すればリンクが揃う。

#### 片方だけを submodule で導入する場合

片方をプラグイン、もう片方を submodule で導入する場合は、次のオプションを使う。

| オプション | リンクを張る場所 | このスクリプトが以前張ったリンクを削除する場所 |
|---|---|---|
| 指定なし | `.claude/skills/` と `.agents/skills/` | なし |
| `--codex-only` | `.agents/skills/` | `.claude/skills/` |
| `--claude-only` | `.claude/skills/` | `.agents/skills/` |

Claude 側をプラグインで導入し、Codex 用のリンクだけを張る場合：

```bash
# 初回
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash -s -- --codex-only
# 導入済みのリポジトリを切り替える場合
.agent-skills/scripts/setup.sh --codex-only

git commit -m "chore: link shared agent skills for Codex only"
```

Codex 側をプラグインで導入し、Claude 用のリンクだけを張る場合：

```bash
# 初回
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash -s -- --claude-only
# 導入済みのリポジトリを切り替える場合
.agent-skills/scripts/setup.sh --claude-only

git commit -m "chore: link shared agent skills for Claude only"
```

どちらも削除するのは、このスクリプトが submodule の `skills/` を指して張ったリンクだけ。リポジトリ固有の実ディレクトリや別の場所へのリンクには触れない。
`--codex-only` と `--claude-only` は同時に指定できない。どちらも `--update` と組み合わせられる。

プラグインと同じスキルへのリンクを両方入れると、同じ description のスキルが2つ並ぶ。
submodule 側が古いままだと、修正前と修正後のどちらが使われるかが会話ごとに変わりうるため、どちらか一方にする。

`--codex-only` / `--claude-only` は記憶されない。付けずに再実行すると両方のリンクを張り直すので、`--update` のときも毎回付ける。

#### 更新方針

submodule は常に `main` の最新を追う。`--update` を付けると、submodule を最新にしてからリンクを張り直す。

```bash
.agent-skills/scripts/setup.sh --update
# --codex-only で導入したリポジトリでは
.agent-skills/scripts/setup.sh --update --codex-only
# --claude-only で導入したリポジトリでは
.agent-skills/scripts/setup.sh --update --claude-only

git commit -m "chore: update shared agent skills"
```

## テスト

`scripts/setup.sh` と `skills/issue-to-pr/scripts/pr_status.sh` のテスト、`bash -n` と `shellcheck` による静的チェック、SKILL.md の検証、プラグインのマニフェストの検証を [GitHub Actions](.github/workflows/ci.yml) で PR ごとに実行している。
ローカルでも同じものを次のコマンドで実行できる（`git`・`jq`・`shellcheck`・`python3` と PyYAML が必要。ネットワークや GitHub の認証は不要）。

```bash
scripts/validate-skills.py      # SKILL.md の検証
scripts/check-plugin-policy.py  # Claude / ChatGPT / Codex の4つのマニフェストの方針チェック
claude plugin validate .        # .claude-plugin/ のマニフェストのスキーマの検証（Claude Code が必要）
tests/run.sh                    # lint とすべてのテスト
tests/run.sh lint               # bash -n と shellcheck だけ
tests/run.sh test               # テストだけ
```

- `validate-skills.py` は、`skills/` 直下の各スキルについて次を確かめ、問題があればファイルと項目を出力して終了コード 1 で終わる
  - `SKILL.md` があり、YAML の frontmatter で始まっている
  - `name` がディレクトリ名と一致し、英小文字・数字・ハイフンだけで64文字以内（先頭・末尾のハイフンとハイフンの連続は不可）。`description` が空でなく1024文字以内（[Agent Skills の仕様](https://agentskills.io/specification)に合わせている）
  - 本文で参照している `references/`・`scripts/`・`assets/` のパスと Markdown のリンク先（相対パス）が、そのスキルのディレクトリに実在する
  - `scripts/` 配下のファイルに実行権限がある
- `check-plugin-policy.py` は、`.claude-plugin/` の2ファイル、ルートの `plugin.json`、`.agents/plugins/marketplace.json` を検証し、違反していれば理由を出力して終了コード 1 で終わる。完全なスキーマ検証ではなく、次の項目を確認する
  - Claude の `marketplace.json` の `name` が `agent-skills` ではない（予約名で、claude.ai のマーケットプレイス同期で拒否される）
  - 両形式の `plugin.json` とカタログのプラグインエントリに `version` がない（Claude での更新方針に合わせ、ChatGPT / Codex 用も省略する）
  - 両形式のプラグイン定義に空でない `name` と `description` があり、それぞれ一致する。各カタログのエントリ名も対応するプラグイン定義と一致する
  - Codex のカタログの各エントリに、有効な `policy.installation`・`policy.authentication` と空でない `category` がある
- `claude plugin validate .` は認証なしで動くので、CI に API キーなどは設定していない。検証ルールの変更で突然失敗しないよう、CI の Claude Code のバージョンは固定している（[ci.yml](.github/workflows/ci.yml) の `CLAUDE_CODE_VERSION`）。`version` がない警告が出るが、上の方針どおりなので `--strict` は付けていない
- `setup.sh` のテストは、一時ディレクトリに共有リポジトリ役のローカル bare リポジトリを作り、`AGENT_SKILLS_URL` で指定して実行する
- `pr_status.sh` のテストは、`PATH` の先頭に偽の `gh`（[tests/fake-bin/gh](tests/fake-bin/gh)）を置いて出力と終了コードを差し替える。各ケースを GraphQL の経路と、GraphQL が 403 になる環境での REST・CCR ルートの経路の両方で実行し、出力が同じになることを確かめる
- `validate-skills.py` のテストは、一時ディレクトリに作ったスキルを1か所ずつ壊し、検証が失敗して問題の箇所が出力されることを確かめる
- `check-plugin-policy.py` のテストも同様に、一時ディレクトリに作ったマニフェストを1か所ずつ壊して確かめる
- CI のジョブの結果は `ci-ok` ジョブにまとまる。ブランチ保護の必須チェックには `ci-ok` だけを指定すればよい

## クラウド環境での設定

### Web 版 Claude Code とプラグイン

Web 版 Claude Code で、claude.ai から同期されたプラグイン（`agent-skills@synced`）が読み込まれるかどうかで、`setup.sh` の使い分けが変わる。

- 読み込まれる場合: Claude 側はプラグインに一本化できる。Codex 側もプラグインで導入するなら submodule は不要。Codex 側を submodule で導入する場合は `--codex-only` を付ける
- 読み込まれない場合: Claude 用のリンクが必要。Codex 側をプラグインで導入するなら `--claude-only` を付け、両方を submodule で導入するならどちらのオプションも付けない

確認結果: **読み込まれる**（2026-10-17 確認）。Web 版 Claude Code でも Claude 側はプラグインに一本化できる。

- claude.ai に登録したプラグインが `~/.claude/plugins/synced/<組織ID>_<ID>/agent-skills/` に同期される
- 3つのスキルが `agent-skills:create-issue`、`agent-skills:issue-to-pr`、`agent-skills:pr-review` として使える
- 同期された `skills/` は `main` の最新と一致していた
- claude.ai に手で取り込んだスキルの同期先（`~/.claude/skills/synced/`）に同名のスキルは無く、重複していない

### GitHub の GraphQL が使えない環境

Web 版 Claude Code のセッションでは、GitHub の GraphQL API が `HTTP 403: GitHub GraphQL is not available from Claude Code sessions` で拒否される（2026-10-20 確認）。`gh api graphql` のほか、内部で GraphQL を使う `gh pr view`・`gh pr checks`・`gh pr list`・`gh issue view`・`gh repo view` なども失敗する。REST（`gh api repos/...`）と、レビュースレッド用の CCR ルート（`gh api repos/{owner}/{repo}/pulls/{n}/ccr/review_threads` など）は使える。

- `skills/issue-to-pr/scripts/pr_status.sh` は、GraphQL が 403 のときに自動で REST と CCR ルートに切り替える
- 各スキルの SKILL.md と [github-commands.md](skills/pr-review/references/github-commands.md) に、GraphQL が使えない環境での代替コマンドを載せている

### submodule の初期化

Codex Cloud や Web 版 Claude Code では submodule が自動で初期化されない場合があるため、
環境設定の setup script に次を入れる。`--remote` を付けると、記録済みのコミットではなく `main` の最新を取得する。

```bash
git submodule update --init --recursive --remote
```

`--remote` で取得した結果が記録済みのコミットより新しいと、`git status` で `.agent-skills` が変更ありと表示される。
意図せずコミットに混ざらないよう、submodule の更新は上の「更新方針」の手順で別コミットにする。
