---
name: "create-issue"
description: Write and create GitHub issues in a fixed format (task and bug templates, title, labels, dependencies). Use when asked to create or draft an issue (e.g. 「issueを作って」「これをissueにしておいて」「バグ報告を書いて」「タスクを分割してissueにして」). A repository's own issue template takes precedence. Not for implementing an issue (use issue-to-pr) or reviewing a PR (use pr-review).
---

# create-issue

Write issues in a fixed format. The goal is issues with the same structure every time, that can be started and checked for completion just by reading them. In particular, the Acceptance criteria are used as is as the completion condition when the issue is later implemented and reviewed (e.g. with issue-to-pr), so write them in a verifiable form.

Commands, and REST replacements for them, are in `references/github-commands.md`. If `gh` fails with `HTTP 403` saying GraphQL is not available, read that file and use the REST commands.

## 1. Prepare the issue

Before writing the body, read `references/issue-format.md` for template precedence, format, metadata and filing order.

## 2. Create the issue

Write the body to a temporary file and pass it with `--body-file`, so shell quoting cannot break it (commands in `references/github-commands.md`).

- If the user explicitly said "create it", create it. If asked only for a draft, or if you filled in much of the content by guessing, show the body and confirm before creating.
- Apply the filing order and parent links from the issue format.
- After creating, post the issue URL.
