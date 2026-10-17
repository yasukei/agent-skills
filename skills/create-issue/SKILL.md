---
name: "create-issue"
description: GitHubのissueを起票するときの書き方（タスク用・不具合用のテンプレート、タイトル、ラベル、依存関係の書き方）。「issueを作って」「issueに起こして」「これをissueにしておいて」「バグ報告を書いて」「タスクを分割してissueにして」など、GitHubにissueを新規作成する・issue本文を下書きするときは必ず使うこと。リポジトリにissueテンプレートがあればそちらを優先する。issueを実装する作業（issue-to-pr）やPRのレビュー（pr-review）には使わない。
---

# GitHub issue の作成

ユーザーが決めた書式でissueを書くためのスキル。目的は「毎回同じ構成で、読めばそのまま着手・完了判定できるissue」を作ること。特に Acceptance criteria は、後で issue-to-pr などで実装・レビューするときの完了条件としてそのまま使われるので、検証可能な形で書く。

## 1. リポジトリのテンプレートを先に確認する

リポジトリ側にテンプレートがあれば、そのリポジトリのルールとしてこのスキルのテンプレートより優先する。確認する場所:

- `.github/ISSUE_TEMPLATE/` 配下の `*.md` と `*.yml` / `*.yaml`（`config.yml` は設定ファイルでテンプレートではない）
- `.github/ISSUE_TEMPLATE.md`、ルートの `ISSUE_TEMPLATE.md`、`docs/ISSUE_TEMPLATE.md`
- 上のどれも無い場合は、オーナーの組織共通リポジトリ `<owner>/.github` の同じ場所

ローカルにクローンがあればファイルを直接見る。無ければ `gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE` などで取得する。

テンプレートが見つかったら:

- 作ろうとしているissueの種類（タスク / 不具合）に合うものを、ファイル名・`name`・`about`・`labels` から選ぶ。
- 見出し構成はテンプレートどおりにし、このスキルの見出しは混ぜない。依存関係など書く場所が無い重要情報だけ、末尾に短く添える。
- YAMLのissue form の場合、GitHubはフォーム送信内容を各項目の `attributes.label` を `### <label>` 見出しにした本文として保存する。同じ形で本文を組み立て、`required: true` の項目は必ず埋める。
- テンプレートの frontmatter / フォーム定義にある `title`（接頭辞）、`labels`、`assignees` を反映する。

種類に合うテンプレートが無い場合（例: bugテンプレートはあるがタスク用が無い）は、その種類だけ下のテンプレートを使う。

## 2. 種類を決める

- **タスク**: 新機能、改善、リファクタ、ドキュメント、CI、調査など「やること」。→ タスクテンプレート
- **不具合**: 期待どおりに動いていないものの修正。→ 不具合テンプレート

迷ったら「今の挙動が仕様に反しているか」で判断する。反していれば不具合。

## 3. タスクテンプレート

```markdown
## Goal

<何を達成するかを1〜2文。なぜ必要かも一言添える>

## Scope

- <やること。まとまりが複数あれば **太字の小見出し** でグループ分けする>

## Out of scope

- <やらないこと。誤解されやすい隣接領域を明示する>

## Acceptance criteria

- <完了判定できる条件。テスト・CI・コマンド結果など観測できる形で>

## Depends on

- #<番号>

Part of #<親issue番号>.
```

書き方のポイント:

- **Goal** は「何を」だけでなく「なぜ」を一言入れる。後から読んだ人が優先度や判断の根拠を追えるようにするため。
- **Scope** は実装者が迷わない粒度で、型名・コマンド名・ファイル名など具体的に書く。前のレビューからの持ち越し事項などは、それと分かる小見出しで分ける。
- **Out of scope** は「今回は入れない」ことを明示してスコープの膨張を防ぐ。本当に無ければ `- None` と書き、セクション自体は残す（書き忘れではなく「無い」ことが分かるように）。
- **Acceptance criteria** は「〜が実装されている」ではなく「〜のテストがあり通る」「CIで〜が実行され成功する」のように、第三者が確認できる形にする。
- **Depends on** は先に終わっている必要があるissueを `- #番号` で並べる（GitHubがタイトル付きで表示する）。無ければ `- None`。
- 親issueから分割したタスクなら末尾に `Part of #<番号>.` を書く。
- 背景資料・参考リンク・未決事項があるときだけ、Acceptance criteria の後に `## Notes` を足す。無理に作らない。

## 4. 不具合テンプレート

```markdown
## Summary

<何が起きているかを1〜2文>

## Steps to reproduce

1. <手順>
2. <手順>

## Expected behavior

<本来どうなるべきか>

## Actual behavior

<実際にどうなるか。エラーメッセージやログはコードブロックで貼る>

## Environment

- Version / commit: <バージョン or コミットハッシュ>
- <OS / ブラウザ / Node など関係するもの>

## Acceptance criteria

- 上の手順で Expected behavior どおりになる
- この不具合を再現する回帰テストが追加され、通る

## Notes

<原因の見当、関連issue/PR、回避策など。無ければこのセクションは省く>
```

書き方のポイント:

- 手順・環境・ログは、ユーザーから聞いたことや自分で確認したことだけを書く。分からない項目は推測で埋めずに `Unknown` と書くか、ユーザーに聞く。作り話の再現手順は調査を誤らせる。
- 原因の見当は事実（Actual behavior）と分けて Notes に書く。症状と仮説が混ざると、仮説が外れたときにissueが読みにくくなる。
- 修正方針が既に決まっている場合も Notes に書く。

## 5. タイトル・ラベル・メタデータ

- タイトルは `<area>: <内容>` の形にする（例: `core: data types, tree IR, and UI–runtime protocol`）。area は対応する `area:*` ラベルなど、リポジトリの既存の区分に合わせる。不具合は修正内容ではなく症状を書く（例: `runtime: TON timer does not fire after coldReset`）。
- ラベルは `gh label list` で既存のものから選ぶ。area系に加えて、不具合なら `bug` があれば付ける。存在しないラベルは勝手に作らない。
- マイルストーンや親issueが分かっていれば設定する。
- タイトルと本文の言語は、そのリポジトリの既存のissueとPRに合わせる（`gh issue list --state all --limit 10` と `gh pr list --state all --limit 10` で確認する）。既存のissueもPRも無ければ日本語で書く。
- セクション名（Goal、Scope、Summary、Steps to reproduce など）は、本文が日本語でも英語のまま使う。ただしリポジトリのテンプレートを使う場合は、そのテンプレートの見出しをそのまま使う。

## 6. 作成する

本文を一時ファイルに書き、`--body-file` で渡す（シェルのクォートで本文が崩れるのを避けるため）。

```bash
gh issue create --repo <owner>/<repo> \
  --title "<title>" --body-file /tmp/issue-body.md \
  --label "<label>" --milestone "<milestone>"
```

- ユーザーが「作って」と明言していればそのまま作成する。下書きを頼まれただけのときや、内容の多くを推測で補ったときは、本文を見せて確認してから作る。
- 親issueがあれば、本文の `Part of #N.` に加えて GitHub の sub-issue としても紐付ける（`gh api` で `POST /repos/<owner>/<repo>/issues/<親番号>/sub_issues`、`sub_issue_id` には子issueの番号ではなく `id` を渡す）。API が使えなければ本文の記述だけで十分。
- 複数issueに分割して作るときは、依存される側から順に作り、Depends on に実際の番号が入るようにする。
- 作成後は issue の URL を伝える。
