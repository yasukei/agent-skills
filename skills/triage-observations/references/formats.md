# Plan and comment formats

## Plan

Identify the log and any item filter. Show one row per selected open item with its ID and log comment link, recommendation, one-line reason, and proposed Status cell. For a new issue, use `issue #<new issue number>` in the plan and say which draft supplies the number. A recovered post uses its real issue number. Show any missing parent link to apply to a recovered issue. For Keep open, name the missing evidence and show `open`.

Show the exact title and Markdown body for each new issue, its included item IDs, and any labels, assignees, milestone or parent relationship to apply. Show each fold target and the exact comment. If several items fold into the same issue, they can share a comment. Use fenced Markdown for the drafts so reviewers can see the retry markers. Ask for approval of the plan before publishing it.

Follow `references/issue-format.md` for issue titles, bodies, metadata and filing order. Use the matching `assets/task-template.md` or `assets/bug-template.md` when no repository template fits.

If a dependency or parent will be filed from the same plan and has no issue number yet, recommend keeping the dependent item open and explain which number is pending. File the prerequisite first, then show the exact dependent draft with the real number in a later plan for approval.

## Fold comment and backlinks

A fold comment briefly explains how the observation fits the existing issue and adds the relevant evidence. Include the same backlinks in new issues. Each item gets a line with its own log comment URL and item ID, even when the items share a comment.

For the built-in templates, put backlinks under `## Notes`. In a task, place that section after `## Depends on`. When using a repository template, put the backlinks in its notes or references section if it has one. Otherwise, append the backlinks without adding a heading. In a task with a parent, place `Part of #N.` on its own line after the backlinks and all other visible content, with only the retry marker after it.

```markdown
- From [the observation log comment](https://github.com/OWNER/REPO/issues/50#issuecomment-123), item `#40-1`.
- From [the observation log comment](https://github.com/OWNER/REPO/issues/50#issuecomment-456), item `#41-2`.

<!-- triage-observations:log=OWNER/REPO#50 items=#40-1,#41-2 -->
```

End each new issue body and fold comment with exactly one marker on its own line. Use the log repository and issue number, then every item covered by that post, comma-separated without spaces in log row order. The log and full item IDs identify posts even when the approved grouping changes.
