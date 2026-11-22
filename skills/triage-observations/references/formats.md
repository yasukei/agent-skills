# Plan, issue and comment formats

## Plan

Identify the log and any item filter. Show one row per selected open item with its ID and log comment link, recommendation, one-line reason, and proposed Status cell. For a new issue, use `issue #<new issue number>` in the plan and say which draft supplies the number. A recovered post uses its real issue number. For Keep open, name the missing evidence and show `open`.

Show the exact title and Markdown body for each new issue, its included item IDs, and any labels, assignees or milestone to apply. Include any parent reference in the issue body. Show each fold target and the exact comment. If several items fold into the same issue, they can share a comment. Use fenced Markdown for the drafts so reviewers can see the retry markers. Ask for approval of the plan before publishing it.

## Issue format

Use the target repository's issue template that fits the task or bug. Look in `.github/ISSUE_TEMPLATE/` for Markdown templates and YAML forms (ignore `config.yml`), then check `.github/ISSUE_TEMPLATE.md`, root `ISSUE_TEMPLATE.md` and `docs/ISSUE_TEMPLATE.md`. If there is no repository template, look in the same locations in the owner's shared `.github` repository.

Keep the template's headings. For a YAML form, use each field's `attributes.label` as a `###` heading and fill every required field. Apply the template's title prefix, labels and assignees. Add essential metadata that has no field after the template body.

When no template fits, use the matching `create-issue` format below. Choose a title in the form `<area>: <summary>` using the repository's existing area names. Choose from existing labels, including `bug` when appropriate. Set a milestone or parent when known and applicable. For a parent, include `Part of #N.` in the body.

### Task

1. `## Goal` — what to achieve and why.
2. `## Scope` — the work to do.
3. `## Out of scope` — related work to leave for later, or `- None`.
4. `## Acceptance criteria` — observable completion conditions.
5. `## Depends on` — prerequisites as `- #N`, or `- None`.

Add `## Notes` before Depends on if background or links need their own section.

### Bug

1. `## Summary` — the bug and its impact.
2. `## Steps to reproduce` — confirmed steps.
3. `## Expected behavior`.
4. `## Actual behavior`.
5. `## Environment` — version or commit and relevant environment details.
6. `## Acceptance criteria` — an observable fix and regression coverage where applicable.
7. `## Notes` — optional investigation or workarounds.

State unknown details as unknown. Distinguish suspected causes from confirmed facts. Include criteria a different person can verify even when the target template places them under another heading.

## Fold comment and backlinks

A fold comment briefly explains how the observation fits the existing issue and adds the relevant evidence. Use the same backlinks in new issue bodies. Each item gets a line with its own log comment URL and item ID, even when the items share a comment.

```markdown
- From [the observation log comment](https://github.com/OWNER/REPO/issues/50#issuecomment-123), item `#40-1`.
- From [the observation log comment](https://github.com/OWNER/REPO/issues/50#issuecomment-456), item `#41-2`.

<!-- triage-observations:log=OWNER/REPO#50 items=#40-1,#41-2 -->
```

End each new issue body and fold comment with exactly one marker on its own line. Use the log repository and issue number, then every item covered by that post, comma-separated without spaces in log row order. The log and full item IDs identify posts even when the approved grouping changes.
