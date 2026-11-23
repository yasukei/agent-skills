#!/usr/bin/env python3
"""Read a collect-observations log and its linked items through GitHub REST."""

import argparse
import json
import re
import subprocess
import sys


LOG_MARKER = "<!-- collect-observations:log -->"
SOURCE_MARKER = re.compile(r"^<!-- collect-observations:source pr=([0-9]+) comment=[0-9]+ -->$", re.M)
TABLE_HEADER = ["Item", "Summary", "Status"]
ITEM_LINK = re.compile(r"\[(#[1-9][0-9]*-[1-9][0-9]*)\]\((https://[^\s)]+)\)")
GROUP = re.compile(r"### PR #([0-9]+) \(issue #([0-9]+)\) — at ([a-fA-F0-9]{4,40})")
ITEM = re.compile(r"\*\*#([0-9]+)-([0-9]+)\*\* — (.+)")
BLOCK = re.compile(
    r"^(?=### PR #|\*\*#[0-9]+-[0-9]+\*\*|Copied from https?://|---[ \t]*$"
    r"|<!-- collect-observations:source )",
    re.M,
)
FIELD = re.compile(r"^-[ \t]+[^\n:：]+[:：][ \t]*", re.M)
FIELD_KEYS = ("observation", "not_raised_because", "related", "source")


def gh_api(path, hostname, paginate=False):
    args = ["gh", "api"]
    if paginate:
        args.append("--paginate")
    try:
        result = subprocess.run(
            [*args, path, "--hostname", hostname],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
        )
    except subprocess.CalledProcessError as error:
        message = error.stderr.strip() or f"exit {error.returncode}"
        raise ValueError(f"gh api {path}: {message}") from error
    return result.stdout


def read_comments(path, hostname):
    # gh --paginate emits successive JSON arrays, including on older gh versions.
    response = gh_api(path, hostname, paginate=True)
    decoder = json.JSONDecoder()
    whitespace = re.compile(r"\s*")
    offset = whitespace.match(response).end()
    if offset == len(response):
        raise ValueError(f"gh api {path}: no JSON pages")
    comments = []
    while offset < len(response):
        page, end = decoder.raw_decode(response, offset)
        if not isinstance(page, list) or any(not isinstance(comment, dict) for comment in page):
            raise ValueError(f"gh api {path}: expected arrays of comments")
        comments.extend(page)
        offset = whitespace.match(response, end).end()
    return comments


def cells(line):
    # Escaped pipes are part of a cell. Match escapes in pairs so even runs of
    # backslashes before a pipe still leave that pipe as a delimiter.
    line = line.strip()
    pipes = [match.start() for match in re.finditer(r"\\.|\|", line) if match[0] == "|"]
    if len(pipes) != 4 or pipes[0] != 0 or pipes[-1] != len(line) - 1:
        return None
    return [line[left + 1:right].strip() for left, right in zip(pipes, pipes[1:])]


def read_rows(body):
    lines = body.splitlines()
    headers = [index for index, line in enumerate(lines) if cells(line) == TABLE_HEADER]
    if len(headers) != 1:
        raise ValueError("expected one Item / Summary / Status table")

    start = headers[0] + 1
    separator = cells(lines[start]) if start < len(lines) else None
    if not separator or any(not re.fullmatch(r":?-+:?", cell) for cell in separator):
        raise ValueError("invalid status table separator")

    rows = []
    seen = set()
    for line in lines[start + 1:]:
        if not line.lstrip().startswith("|"):
            break
        columns = cells(line)
        link = ITEM_LINK.fullmatch(columns[0]) if columns else None
        if not link or not columns[2]:
            raise ValueError(f"invalid status row: {line}")
        item_id, comment_url = link.groups()
        if item_id in seen:
            raise ValueError(f"duplicate status row: {item_id}")
        seen.add(item_id)
        rows.append({"id": item_id, "summary": columns[1], "status": columns[2], "comment_url": comment_url})
    return rows


def read_fields(text):
    # The writer translates the labels and keeps their order.
    labels = list(FIELD.finditer(text))
    if len(labels) != len(FIELD_KEYS) or text[:labels[0].start()].strip():
        return None
    ends = [label.start() for label in labels[1:]] + [len(text)]
    return {
        key: text[label.end():end].strip()
        for key, label, end in zip(FIELD_KEYS, labels, ends)
    }


def read_items(body):
    body = body.replace("\r\n", "\n")
    source_prs = set(SOURCE_MARKER.findall(body))
    items = {}
    group = None
    for block in BLOCK.split(body):
        header, _, text = block.partition("\n")
        if header.startswith("### PR #"):
            group = GROUP.fullmatch(header.rstrip())
            continue
        match = ITEM.fullmatch(header.rstrip())
        if not match:
            continue
        pr, index, location = match.groups()
        item_id = f"#{pr}-{index}"
        fields = read_fields(text)
        if item_id in items or not group or group[1] != pr or pr not in source_prs or fields is None:
            items[item_id] = None
            continue
        items[item_id] = {"pr": int(pr), "issue": int(group[2]), "sha": group[3], "location": location, **fields}
    return items


def read_log(repo, number, hostname, *, rows_only=False):
    path = f"repos/{repo}/issues/{number}"
    issue = json.loads(gh_api(path, hostname))
    if not isinstance(issue, dict) or issue.get("number") != number:
        raise ValueError(f"gh api {path}: expected issue #{number}")
    if issue.get("pull_request") is not None:
        raise ValueError(f"{repo}#{number} is a pull request")
    body = issue.get("body")
    if not isinstance(body, str) or body.rstrip().split("\n")[-1] != LOG_MARKER:
        raise ValueError(f"{repo}#{number} is missing the log marker")

    rows = read_rows(body)
    if rows and not rows_only:
        comments = read_comments(f"{path}/comments?per_page=100", hostname)
        linked_urls = {row["comment_url"].casefold() for row in rows}
        linked_items = {
            comment["html_url"].casefold(): read_items(comment["body"])
            for comment in comments
            if isinstance(comment.get("html_url"), str)
            and comment["html_url"].casefold() in linked_urls
            and isinstance(comment.get("body"), str)
        }
        for row in rows:
            row["item"] = linked_items.get(row["comment_url"].casefold(), {}).get(row["id"])
            if row["item"] is None:
                row["item_error"] = "Item missing, ambiguous, or malformed in its linked log comment"
    return {"repository": repo, "number": number, "url": issue.get("html_url"), "rows": rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", metavar="OWNER/REPO")
    parser.add_argument("log", metavar="ISSUE")
    parser.add_argument("--hostname", default="github.com", help="GitHub host (default: github.com)")
    parser.add_argument("--rows-only", action="store_true", help="Read status rows without fetching comments")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository):
        parser.error("repository must be OWNER/REPO")
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", args.hostname):
        parser.error("hostname must be a GitHub host name")
    number = args.log[1:] if args.log.startswith("#") else args.log
    if not re.fullmatch(r"[1-9][0-9]*", number):
        parser.error("log must be a positive issue number")
    try:
        result = read_log(args.repository, int(number), args.hostname, rows_only=args.rows_only)
    except (OSError, ValueError) as error:
        parser.exit(2, f"{parser.prog}: {error}\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
