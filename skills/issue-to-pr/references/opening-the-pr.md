# Opening and updating the PR

Read this when opening the PR (step 5 in SKILL.md) and after pushing fixes for review comments (step 6).

## Opening the PR

- **Do not open it as a draft**; publish it directly.
- Use the repository's PR template (e.g. `.github/pull_request_template.md`) if there is one; keep its headings as they are. Otherwise use `assets/pr-template.md` with its headings kept in English. Write the body following "Language" in SKILL.md.
- Set "Related issue" to `Closes #<number>`.
- Check only the testing boxes you actually did.
- In "Review focus", honestly list the parts you are unsure about and the design decisions, so the reviewer spends time there.
- For sections that do not apply (e.g. screenshots with no UI change), write "None" or delete them.

After creating it, post the PR URL in chat.

## Updating the title and body after fixes

After pushing fixes, **check that the PR title and body still match the implementation, and update them if not.** With a squash merge the PR body becomes the commit message, so a stale body leaves a wrong record, and a mismatch is itself a review finding that costs another round.

- Check the title and every section of the body.
- Fetch the current title and body from the PR and edit that, not the local file used at creation: it may be stale, or someone may have edited it on GitHub.
- Rewrite only the parts that disagree, so they describe the final implementation. Leave content unrelated to describing the implementation (HTML comments, content added by others or by tools) as is.
- Do not append a change history of which commit fixed what; the thread replies and commits already record it.
- Update at the same time as the push, like the thread replies, so the body matches when the reviewer looks next.
