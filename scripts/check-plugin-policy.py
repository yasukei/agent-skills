#!/usr/bin/env python3
"""Claude / ChatGPT / Codex のマニフェストが、リポジトリの方針に沿っているかを確かめる。

  scripts/check-plugin-policy.py         リポジトリの4つのマニフェストを検証する
  scripts/check-plugin-policy.py <root>  <root> 内のマニフェストを検証する（テスト用）

完全なスキーマ検証ではなく、配布に必要な項目とこのリポジトリの方針を見る。
Claude のスキーマ検証は引き続き `claude plugin validate .` で行う。
- Claude の marketplace.json の name が予約名 agent-skills ではない
- plugin.json と marketplace.json のプラグインエントリに version がない
- Claude と Agent Plugins のプラグイン名・説明文、および各カタログのエントリ名が一致する
- Codex のカタログの各エントリに policy.installation / policy.authentication / category がある

問題があれば「どのファイルのどの項目か」と理由を標準エラーに出し、終了コード 1 で終わる。
"""

import json
import os
import sys

# 小文字で書く。claude.ai が大文字小文字を区別するかは未確認なので、区別せずに比較する
RESERVED_MARKETPLACE_NAMES = {"agent-skills"}

VERSION_REASON = (
    "このリポジトリでは version を書きません。Claude では、書くとその文字列を変えるまで"
    "更新が配布されません。ChatGPT / Codex 用も省略する方針に統一しています"
)

CLAUDE_MARKETPLACE = os.path.join(".claude-plugin", "marketplace.json")
CLAUDE_PLUGIN = os.path.join(".claude-plugin", "plugin.json")
CODEX_MARKETPLACE = os.path.join(".agents", "plugins", "marketplace.json")
PORTABLE_PLUGIN = "plugin.json"
MANIFESTS = (CLAUDE_MARKETPLACE, CLAUDE_PLUGIN, CODEX_MARKETPLACE, PORTABLE_PLUGIN)


def load_json(path, rel, errors):
    if not os.path.isfile(path):
        errors.append(f"{rel}: ありません")
        return None
    try:
        with open(path, encoding="utf-8") as fp:
            data = json.load(fp)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        errors.append(f"{rel}: JSON として解析できません: {e}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{rel}: JSON のオブジェクトになっていません")
        return None
    return data


def check_marketplace(data, rel, errors, plugin=None):
    name = data.get("name")
    if rel == CLAUDE_MARKETPLACE and isinstance(name, str) and name.lower() in RESERVED_MARKETPLACE_NAMES:
        errors.append(
            f"{rel}: name: {name!r} は予約名で、claude.ai のマーケットプレイス同期で拒否されます。"
            "別の名前（例: 'yasukei-agent-skills'）にしてください"
        )
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        errors.append(f"{rel}: plugins: 空でない配列にしてください")
        return
    for i, entry in enumerate(plugins):
        label = f"plugins[{i}]"
        if not isinstance(entry, dict):
            errors.append(f"{rel}: {label}: オブジェクトにしてください")
            continue
        if plugin is not None and entry.get("name") != plugin.get("name"):
            errors.append(f"{rel}: {label}.name: プラグイン定義の name と一致させてください")
        if "version" in entry:
            label = entry.get("name", i)
            errors.append(f"{rel}: plugins[{i}]（{label}）: version: {VERSION_REASON}")
        if rel == CODEX_MARKETPLACE:
            policy = entry.get("policy")
            if not isinstance(policy, dict):
                policy = {}
            for key, values in (
                ("installation", ("AVAILABLE", "INSTALLED_BY_DEFAULT", "NOT_AVAILABLE")),
                ("authentication", ("ON_INSTALL", "ON_USE")),
            ):
                if policy.get(key) not in values:
                    errors.append(
                        f"{rel}: plugins[{i}].policy.{key}: {', '.join(values)} のいずれかを指定してください"
                    )
            category = entry.get("category")
            if not isinstance(category, str) or not category.strip():
                errors.append(f"{rel}: plugins[{i}].category: 空でない文字列を指定してください")


def check_plugin(data, rel, errors):
    for key in ("name", "description"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{rel}: {key}: 空でない文字列を指定してください")
    if "version" in data:
        errors.append(f"{rel}: version: {VERSION_REASON}")


def check(root):
    errors = []
    manifests = {rel: load_json(os.path.join(root, rel), rel, errors) for rel in MANIFESTS}
    for rel in (CLAUDE_PLUGIN, PORTABLE_PLUGIN):
        if manifests[rel] is not None:
            check_plugin(manifests[rel], rel, errors)
    for rel, plugin_rel in ((CLAUDE_MARKETPLACE, CLAUDE_PLUGIN), (CODEX_MARKETPLACE, PORTABLE_PLUGIN)):
        if manifests[rel] is not None:
            check_marketplace(manifests[rel], rel, errors, manifests[plugin_rel])
    claude = manifests[CLAUDE_PLUGIN]
    portable = manifests[PORTABLE_PLUGIN]
    if claude is not None and portable is not None:
        for key in ("name", "description"):
            if portable.get(key) != claude.get(key):
                errors.append(f"{PORTABLE_PLUGIN}: {key}: {CLAUDE_PLUGIN} の {key} と一致させてください")
    return errors


def main(argv):
    if len(argv) > 2:
        print(f"usage: {argv[0]} [root]", file=sys.stderr)
        return 1
    if len(argv) == 2:
        root = argv[1]
    else:
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    root = os.path.normpath(os.path.abspath(root))
    if not os.path.isdir(root):
        print(f"{root}: ディレクトリがありません", file=sys.stderr)
        return 1

    errors = check(root)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(f"{len(errors)} 件の問題があります", file=sys.stderr)
        return 1
    print(f"plugin policy ok: {', '.join(MANIFESTS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
