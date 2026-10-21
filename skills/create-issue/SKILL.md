---
name: "create-issue"
description: Write and create GitHub issues in a fixed format (task and bug templates, title, labels, dependencies). Use when asked to create or draft an issue (e.g. 「issueを作って」「これをissueにしておいて」「バグ報告を書いて」「タスクを分割してissueにして」). A repository's own issue template takes precedence. Not for implementing an issue (use issue-to-pr) or reviewing a PR (use pr-review).
---

# create-issue

Write issues in the format the user decided on. The goal is issues with the same structure every time, that can be started and checked for completion just by reading them. In particular, the Acceptance criteria are used as is as the completion condition when the issue is later implemented and reviewed (e.g. with issue-to-pr), so write them in a verifiable form.

Commands, and REST replacements for them, are in `references/github-commands.md`. If `gh` fails with `HTTP 403` saying GraphQL is not available, read that file and use the REST commands.

## 1. Check the repository's templates first

A template in the repository is that repository's rule and takes precedence over this skill's templates. Look in:

- `*.md` and `*.yml` / `*.yaml` under `.github/ISSUE_TEMPLATE/` (`config.yml` is configuration, not a template)
- `.github/ISSUE_TEMPLATE.md`, `ISSUE_TEMPLATE.md` at the root, `docs/ISSUE_TEMPLATE.md`
- If none of these exist, the same places in the owner's shared repository `<owner>/.github`

Read the files directly if there is a local clone; otherwise fetch them with `gh api` (see `references/github-commands.md`).

When a template is found:

- Pick the one that fits the kind of issue (task or bug) from its file name, `name`, `about` and `labels`.
- Follow its headings exactly and do not mix in this skill's headings. Only important information with nowhere to go, such as dependencies, is added briefly at the end.
- For a YAML issue form, GitHub stores the submitted form as a body with each field's `attributes.label` as a `### <label>` heading. Build the body the same way and fill every field with `required: true`.
- Apply the `title` (prefix), `labels` and `assignees` from the template's frontmatter or form definition.

If no template fits the kind (e.g. there is a bug template but none for tasks), use this skill's template for that kind only.

## 2. Decide the kind

- **Task**: a new feature, improvement, refactoring, documentation, CI, investigation: "something to do". → `assets/task-template.md`
- **Bug**: fixing something that does not work as expected. → `assets/bug-template.md`

When unsure, ask "does the current behavior violate the spec?" If it does, it is a bug.

## 3. Task template

Use `assets/task-template.md` (Goal / Scope / Out of scope / Acceptance criteria / Depends on). Guidelines:

- **Goal** says why as well as what, so later readers can follow the priority and the reasoning behind decisions.
- **Scope** is specific enough that the implementer does not hesitate: name types, commands and files. Put items carried over from an earlier review, etc. under their own subheading.
- **Out of scope** states what is not included this time, to stop the scope from growing. If there really is nothing, write `- None` and keep the section, so it reads as "nothing" rather than "forgotten".
- **Acceptance criteria** are checkable by a third party: not "X is implemented" but "tests for X exist and pass" or "CI runs X and it succeeds".
- **Depends on** lists the issues that must be finished first as `- #<number>` (GitHub shows them with their titles). If none, `- None`.
- For a task split from a parent issue, end with `Part of #<number>.`
- Add `## Notes` after Acceptance criteria only when there is background material, reference links or open questions. Do not force it.

## 4. Bug template

Use `assets/bug-template.md` (Summary / Steps to reproduce / Expected behavior / Actual behavior / Environment / Acceptance criteria / Notes). Guidelines:

- Write only steps, environment and logs that the user told you or that you confirmed yourself. Do not fill unknown items with guesses: write `Unknown` or ask the user. Made-up reproduction steps mislead the investigation.
- Put the suspected cause in Notes, separate from the facts (Actual behavior). When symptoms and hypotheses are mixed, the issue becomes hard to read once a hypothesis turns out wrong.
- If the fix approach is already decided, also write it in Notes.

## 5. Title, labels and metadata

- Title: `<area>: <summary>` (e.g. `core: data types, tree IR, and UI–runtime protocol`). Match the area to the repository's existing divisions, such as the corresponding `area:*` label. For a bug, describe the symptom, not the fix (e.g. `runtime: TON timer does not fire after coldReset`).
- Labels: choose from existing ones (`gh label list`). Besides area labels, add `bug` to a bug if it exists. Do not create labels that do not exist.
- Set the milestone and parent issue if known.
- Language: the title and body follow the language of the repository's existing issues and PRs (check with `gh issue list --state all --limit 10` and `gh pr list --state all --limit 10`). If there are none, use the user's language.
- Section headings (Goal, Scope, Summary, Steps to reproduce, etc.) stay in English even when the body is in another language. When using the repository's template, keep that template's headings as they are.

## 6. Create the issue

Write the body to a temporary file and pass it with `--body-file`, so shell quoting cannot break it (commands in `references/github-commands.md`).

- If the user explicitly said "create it", create it. If asked only for a draft, or if you filled in much of the content by guessing, show the body and confirm before creating.
- If there is a parent issue, link it as a GitHub sub-issue as well as writing `Part of #N.` in the body (`sub_issue_id` is the child issue's `id`, not its number). If the API is unavailable, the line in the body is enough.
- When splitting into several issues, create the ones others depend on first, so that Depends on contains real numbers.
- After creating, post the issue URL.
