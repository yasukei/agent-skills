#!/usr/bin/env python3
"""skills/*/SKILL.md の frontmatter と、SKILL.md から参照しているファイルを検証する。

  scripts/validate-skills.py               リポジトリの skills/ を検証する
  scripts/validate-skills.py <skills_dir>  指定したディレクトリを検証する（テスト用）

問題があれば「どのファイルのどの項目か」を標準エラーに出し、終了コード 1 で終わる。
name と description の制限は Agent Skills の仕様（https://agentskills.io/specification）に合わせている。
"""

import os
import re
import stat
import sys
from urllib.parse import unquote

try:
    import yaml
except ImportError:
    print("PyYAML が見つかりません（pip install pyyaml などで入れてください）", file=sys.stderr)
    sys.exit(2)

NAME_MAX = 64
DESCRIPTION_MAX = 1024
# 英小文字・数字をハイフンでつなぐ形。先頭・末尾のハイフンと、ハイフンの連続は認めない
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# 本文中の references/... scripts/... assets/... を拾う。
# 直前が ASCII の英数字・ドット・スラッシュ・ハイフンのもの（skills/x/scripts/... や .github/scripts/... など）は、
# スキル内の相対パスではないので対象外にする。
# 日本語の直後（「詳細はreferences/a.mdを読む」）は対象にしたいので、\w ではなく ASCII に限る
DIR_REF_RE = re.compile(r"(?<![A-Za-z0-9_./-])((?:references|scripts|assets)/[A-Za-z0-9._/-]*)")
# Markdown のリンク [text](target) と画像 ![alt](target)
LINK_RE = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'][^)]*[\"'])?\s*\)")
URL_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def split_frontmatter(text):
    """(frontmatter の文字列, 本文) を返す。frontmatter で始まっていなければ None を返す"""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        return None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") == "---":
            return "".join(lines[1:i]), "".join(lines[i + 1:])
    return None


def check_frontmatter(skill, rel, front, errors):
    try:
        data = yaml.safe_load(front)
    except yaml.YAMLError as e:
        errors.append(f"{rel}: frontmatter を YAML として解析できません: {e}")
        return
    if not isinstance(data, dict):
        errors.append(f"{rel}: frontmatter がキーと値の組（マッピング）になっていません")
        return

    if "name" not in data:
        errors.append(f"{rel}: name: ありません")
    else:
        name = data["name"]
        if not isinstance(name, str):
            errors.append(f"{rel}: name: 文字列ではありません: {name!r}")
        else:
            if not NAME_RE.fullmatch(name):
                errors.append(
                    f"{rel}: name: 英小文字・数字・ハイフンだけで書き、先頭・末尾のハイフンや"
                    f"ハイフンの連続は使えません: {name!r}"
                )
            if len(name) > NAME_MAX:
                errors.append(f"{rel}: name: {NAME_MAX}文字を超えています（{len(name)}文字）")
            if name != skill:
                errors.append(f"{rel}: name: ディレクトリ名 {skill!r} と一致しません: {name!r}")

    if "description" not in data:
        errors.append(f"{rel}: description: ありません")
    else:
        desc = data["description"]
        if not isinstance(desc, str):
            errors.append(f"{rel}: description: 文字列ではありません: {desc!r}")
        elif not desc.strip():
            errors.append(f"{rel}: description: 空です")
        elif len(desc) > DESCRIPTION_MAX:
            errors.append(
                f"{rel}: description: {DESCRIPTION_MAX}文字を超えています（{len(desc)}文字）"
            )


def referenced_paths(body):
    """本文から参照しているスキル内の相対パスを、出現順・重複なしで返す"""
    found = []
    for m in DIR_REF_RE.finditer(body):
        # 文末のピリオドなどはパスに含めない
        found.append(m.group(1).rstrip("."))
    for m in LINK_RE.finditer(body):
        target = m.group(1)
        if URL_SCHEME_RE.match(target) or target.startswith(("#", "/")):
            continue
        target = unquote(re.split(r"[#?]", target, maxsplit=1)[0])
        if target:
            found.append(target)
    return list(dict.fromkeys(found))


def check_references(skill_dir, rel, body, errors):
    for ref in referenced_paths(body):
        resolved = os.path.normpath(os.path.join(skill_dir, ref))
        if os.path.relpath(resolved, skill_dir).split(os.sep)[0] == "..":
            errors.append(f"{rel}: 参照 {ref}: スキルのディレクトリの外を指しています")
        elif not os.path.exists(resolved):
            errors.append(f"{rel}: 参照 {ref}: ファイルがありません")


def check_scripts(skills_dir, skill_dir, errors):
    scripts_dir = os.path.join(skill_dir, "scripts")
    for root, dirs, files in os.walk(scripts_dir):
        dirs.sort()
        for f in sorted(files):
            path = os.path.join(root, f)
            if not os.path.isfile(path):
                continue
            if not os.stat(path).st_mode & stat.S_IXUSR:
                rel = os.path.relpath(path, os.path.dirname(skills_dir))
                errors.append(f"{rel}: 実行権限がありません")


def validate(skills_dir):
    errors = []
    skills = sorted(
        d for d in os.listdir(skills_dir)
        if not d.startswith(".") and os.path.isdir(os.path.join(skills_dir, d))
    )
    if not skills:
        errors.append(f"{skills_dir}: スキルのディレクトリがありません")
    base = os.path.dirname(skills_dir)
    for skill in skills:
        skill_dir = os.path.join(skills_dir, skill)
        path = os.path.join(skill_dir, "SKILL.md")
        rel = os.path.relpath(path, base)
        if not os.path.isfile(path):
            errors.append(f"{rel}: ありません")
            continue
        with open(path, encoding="utf-8-sig") as fp:
            parts = split_frontmatter(fp.read())
        if parts is None:
            errors.append(f"{rel}: '---' で囲んだ YAML の frontmatter で始まっていません")
        else:
            front, body = parts
            check_frontmatter(skill, rel, front, errors)
            check_references(skill_dir, rel, body, errors)
        check_scripts(skills_dir, skill_dir, errors)
    return skills, errors


def main(argv):
    if len(argv) > 2:
        print(f"usage: {argv[0]} [skills_dir]", file=sys.stderr)
        return 1
    if len(argv) == 2:
        skills_dir = argv[1]
    else:
        skills_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills")
    skills_dir = os.path.normpath(os.path.abspath(skills_dir))
    if not os.path.isdir(skills_dir):
        print(f"{skills_dir}: ディレクトリがありません", file=sys.stderr)
        return 1

    skills, errors = validate(skills_dir)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(f"{len(errors)} 件の問題があります", file=sys.stderr)
        return 1
    print(f"{len(skills)} skills ok: {', '.join(skills)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
