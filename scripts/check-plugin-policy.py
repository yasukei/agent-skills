#!/usr/bin/env python3
"""Check that the Claude / ChatGPT / Codex manifests follow the repository's policy.

  scripts/check-plugin-policy.py         check the repository's four manifests
  scripts/check-plugin-policy.py <root>  check the manifests in <root> (for tests)

This is not a full schema validation; it checks the fields needed for distribution and
this repository's policy. Claude's schema is still validated by `claude plugin validate .`.
- The name in Claude's marketplace.json is not the reserved name agent-skills
- plugin.json and the plugin entries in marketplace.json have no version
- The Claude and Agent Plugins plugin name and description, and each catalog's entry name, match
- Each entry in the Codex catalog has policy.installation / policy.authentication / category

On problems, prints which file and field, and why, to stderr and exits with status 1.
"""

import json
import os
import sys

# Write in lowercase. Whether claude.ai is case-sensitive is unverified, so compare case-insensitively
RESERVED_MARKETPLACE_NAMES = {"agent-skills"}

VERSION_REASON = (
    "this repository does not set version. In Claude, updates are not distributed until "
    "the string changes. The ChatGPT / Codex manifests omit it too, for consistency"
)

CLAUDE_MARKETPLACE = os.path.join(".claude-plugin", "marketplace.json")
CLAUDE_PLUGIN = os.path.join(".claude-plugin", "plugin.json")
CODEX_MARKETPLACE = os.path.join(".agents", "plugins", "marketplace.json")
PORTABLE_PLUGIN = "plugin.json"
MANIFESTS = (CLAUDE_MARKETPLACE, CLAUDE_PLUGIN, CODEX_MARKETPLACE, PORTABLE_PLUGIN)


def load_json(path, rel, errors):
    if not os.path.isfile(path):
        errors.append(f"{rel}: not found")
        return None
    try:
        with open(path, encoding="utf-8") as fp:
            data = json.load(fp)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        errors.append(f"{rel}: cannot parse as JSON: {e}")
        return None
    if not isinstance(data, dict):
        errors.append(f"{rel}: not a JSON object")
        return None
    return data


def check_marketplace(data, rel, errors, plugin=None):
    name = data.get("name")
    if rel == CLAUDE_MARKETPLACE and isinstance(name, str) and name.lower() in RESERVED_MARKETPLACE_NAMES:
        errors.append(
            f"{rel}: name: {name!r} is a reserved name and is rejected by claude.ai's marketplace sync. "
            "Use another name (e.g. 'yasukei-agent-skills')"
        )
    plugins = data.get("plugins")
    if not isinstance(plugins, list) or not plugins:
        errors.append(f"{rel}: plugins: must be a non-empty array")
        return
    for i, entry in enumerate(plugins):
        label = f"plugins[{i}]"
        if not isinstance(entry, dict):
            errors.append(f"{rel}: {label}: must be an object")
            continue
        if plugin is not None and entry.get("name") != plugin.get("name"):
            errors.append(f"{rel}: {label}.name: must match the name in the plugin definition")
        if "version" in entry:
            label = entry.get("name", i)
            errors.append(f"{rel}: plugins[{i}] ({label}): version: {VERSION_REASON}")
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
                        f"{rel}: plugins[{i}].policy.{key}: must be one of {', '.join(values)}"
                    )
            category = entry.get("category")
            if not isinstance(category, str) or not category.strip():
                errors.append(f"{rel}: plugins[{i}].category: must be a non-empty string")


def check_plugin(data, rel, errors):
    for key in ("name", "description"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            errors.append(f"{rel}: {key}: must be a non-empty string")
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
                errors.append(f"{PORTABLE_PLUGIN}: {key}: must match the {key} in {CLAUDE_PLUGIN}")
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
        print(f"{root}: directory not found", file=sys.stderr)
        return 1

    errors = check(root)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(f"{len(errors)} problem(s) found", file=sys.stderr)
        return 1
    print(f"plugin policy ok: {', '.join(MANIFESTS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
