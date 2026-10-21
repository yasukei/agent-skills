#!/usr/bin/env python3
"""Validate skills/*/SKILL.md (frontmatter, referenced files, size) and the files shared between skills.

  scripts/validate-skills.py               validate the repository's skills/
  scripts/validate-skills.py <skills_dir>  validate the given directory (for tests)

On problems, prints which file and field to stderr and exits with status 1.
The limits on name and description follow the Agent Skills spec (https://agentskills.io/specification).
"""

import os
import re
import stat
import sys
from urllib.parse import unquote

try:
    import yaml
except ImportError:
    print("PyYAML not found (install it, e.g. with pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

NAME_MAX = 64
DESCRIPTION_MAX = 1024
# Lowercase letters and digits joined by hyphens. No leading, trailing or consecutive hyphens
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# Size budget of SKILL.md, because agents load the whole file into context. Bytes and lines stand in for tokens
SKILL_MAX_LINES = 200
SKILL_MAX_BYTES = 10000

# Groups of files, relative to skills/, that must stay byte-identical. Each skill is installed on its own,
# so a file used by several skills is copied into each of them.
# A group is skipped when none of its skills exists (e.g. a skills directory created by the tests)
SHARED_FILES = [
    ("issue-to-pr/references/review-protocol.md", "pr-review/references/review-protocol.md"),
]

# Pick up references/... scripts/... assets/... in the body.
# Matches preceded by an ASCII letter, digit, dot, slash or hyphen (skills/x/scripts/..., .github/scripts/..., etc.)
# are not relative paths inside the skill, so they are skipped.
# Matches right after non-ASCII text such as Japanese should count, so the lookbehind uses ASCII, not \w
DIR_REF_RE = re.compile(r"(?<![A-Za-z0-9_./-])((?:references|scripts|assets)/[A-Za-z0-9._/-]*)")
# Markdown links [text](target) and images ![alt](target)
LINK_RE = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+[\"'][^)]*[\"'])?\s*\)")
URL_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def split_frontmatter(text):
    """Return (frontmatter string, body), or None if the text does not start with a frontmatter"""
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
        errors.append(f"{rel}: cannot parse the frontmatter as YAML: {e}")
        return
    if not isinstance(data, dict):
        errors.append(f"{rel}: the frontmatter is not a mapping of keys and values")
        return

    if "name" not in data:
        errors.append(f"{rel}: name: missing")
    else:
        name = data["name"]
        if not isinstance(name, str):
            errors.append(f"{rel}: name: not a string: {name!r}")
        else:
            if not NAME_RE.fullmatch(name):
                errors.append(
                    f"{rel}: name: use only lowercase letters, digits and hyphens, with no leading, "
                    f"trailing or consecutive hyphens: {name!r}"
                )
            if len(name) > NAME_MAX:
                errors.append(f"{rel}: name: longer than {NAME_MAX} characters ({len(name)})")
            if name != skill:
                errors.append(f"{rel}: name: does not match the directory name {skill!r}: {name!r}")

    if "description" not in data:
        errors.append(f"{rel}: description: missing")
    else:
        desc = data["description"]
        if not isinstance(desc, str):
            errors.append(f"{rel}: description: not a string: {desc!r}")
        elif not desc.strip():
            errors.append(f"{rel}: description: empty")
        elif len(desc) > DESCRIPTION_MAX:
            errors.append(
                f"{rel}: description: longer than {DESCRIPTION_MAX} characters ({len(desc)})"
            )


def referenced_paths(body):
    """Return the relative paths inside the skill that the body references, in order of appearance, without duplicates"""
    found = []
    for m in DIR_REF_RE.finditer(body):
        # Do not include a trailing period in the path
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
            errors.append(f"{rel}: reference {ref}: points outside the skill directory")
        elif not os.path.exists(resolved):
            errors.append(f"{rel}: reference {ref}: file not found")


def check_size(rel, data, errors):
    lines = len(data.splitlines())
    if lines > SKILL_MAX_LINES:
        errors.append(f"{rel}: longer than {SKILL_MAX_LINES} lines ({lines})")
    if len(data) > SKILL_MAX_BYTES:
        errors.append(f"{rel}: larger than {SKILL_MAX_BYTES} bytes ({len(data)})")


def check_shared_files(skills_dir, errors):
    base = os.path.dirname(skills_dir)
    for group in SHARED_FILES:
        if not any(os.path.isdir(os.path.join(skills_dir, f.split("/")[0])) for f in group):
            continue
        contents = {}
        for f in group:
            path = os.path.join(skills_dir, f)
            rel = os.path.relpath(path, base)
            if not os.path.isfile(path):
                errors.append(f"{rel}: shared file not found")
                continue
            with open(path, "rb") as fp:
                contents[rel] = fp.read()
        rels = list(contents)
        for rel in rels[1:]:
            if contents[rel] != contents[rels[0]]:
                errors.append(f"{rels[0]} and {rel}: shared files differ (they must be byte-identical)")


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
                errors.append(f"{rel}: not executable")


def validate(skills_dir):
    errors = []
    skills = sorted(
        d for d in os.listdir(skills_dir)
        if not d.startswith(".") and os.path.isdir(os.path.join(skills_dir, d))
    )
    if not skills:
        errors.append(f"{skills_dir}: no skill directories")
    base = os.path.dirname(skills_dir)
    for skill in skills:
        skill_dir = os.path.join(skills_dir, skill)
        path = os.path.join(skill_dir, "SKILL.md")
        rel = os.path.relpath(path, base)
        if not os.path.isfile(path):
            errors.append(f"{rel}: not found")
            continue
        with open(path, "rb") as fp:
            data = fp.read()
        check_size(rel, data, errors)
        parts = split_frontmatter(data.decode("utf-8-sig"))
        if parts is None:
            errors.append(f"{rel}: does not start with a YAML frontmatter enclosed in '---'")
        else:
            front, body = parts
            check_frontmatter(skill, rel, front, errors)
            check_references(skill_dir, rel, body, errors)
        check_scripts(skills_dir, skill_dir, errors)
    check_shared_files(skills_dir, errors)
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
        print(f"{skills_dir}: directory not found", file=sys.stderr)
        return 1

    skills, errors = validate(skills_dir)
    for e in errors:
        print(e, file=sys.stderr)
    if errors:
        print(f"{len(errors)} problem(s) found", file=sys.stderr)
        return 1
    print(f"{len(skills)} skills ok: {', '.join(skills)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
