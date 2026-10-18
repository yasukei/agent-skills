#!/usr/bin/env python3
""".claude-plugin/ のマニフェストが、このリポジトリの方針に沿っているかを確かめる。

  scripts/check-plugin-policy.py         リポジトリの .claude-plugin/ を検証する
  scripts/check-plugin-policy.py <root>  <root>/.claude-plugin/ を検証する（テスト用）

スキーマの検証は `claude plugin validate .` に任せ、ここではそれでは検出できない方針だけを見る。
- marketplace.json の name が予約名 agent-skills ではない（claude.ai のマーケットプレイス同期で拒否される）
- plugin.json と marketplace.json のプラグインエントリに version がない
  （書くとその文字列を変えるまで更新が配布されない。書かなければコミット SHA で更新される）

問題があれば「どのファイルのどの項目か」と理由を標準エラーに出し、終了コード 1 で終わる。
"""

import json
import os
import sys

RESERVED_MARKETPLACE_NAMES = {"agent-skills"}

VERSION_REASON = (
    "このリポジトリでは version を書きません。書くとその文字列を変えるまで更新が配布されません"
    "（書かなければコミット SHA で決まり、main へのコミットごとに配布されます）"
)


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


def check_marketplace(data, rel, errors):
    name = data.get("name")
    if isinstance(name, str) and name in RESERVED_MARKETPLACE_NAMES:
        errors.append(
            f"{rel}: name: {name!r} は予約名で、claude.ai のマーケットプレイス同期で拒否されます。"
            "別の名前（例: 'yasukei-agent-skills'）にしてください"
        )
    plugins = data.get("plugins")
    if not isinstance(plugins, list):
        return
    for i, entry in enumerate(plugins):
        if isinstance(entry, dict) and "version" in entry:
            label = entry.get("name", i)
            errors.append(f"{rel}: plugins[{i}]（{label}）: version: {VERSION_REASON}")


def check_plugin(data, rel, errors):
    if "version" in data:
        errors.append(f"{rel}: version: {VERSION_REASON}")


def check(root):
    errors = []
    marketplace_rel = os.path.join(".claude-plugin", "marketplace.json")
    plugin_rel = os.path.join(".claude-plugin", "plugin.json")

    marketplace = load_json(os.path.join(root, marketplace_rel), marketplace_rel, errors)
    if marketplace is not None:
        check_marketplace(marketplace, marketplace_rel, errors)

    plugin = load_json(os.path.join(root, plugin_rel), plugin_rel, errors)
    if plugin is not None:
        check_plugin(plugin, plugin_rel, errors)
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
    print("plugin policy ok: .claude-plugin/marketplace.json, .claude-plugin/plugin.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
