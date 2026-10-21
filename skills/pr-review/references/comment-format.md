# Comment formats

Formats for what this skill posts on the PR. Write the content in the comment language (see "Language" in SKILL.md). Keep the labels (`P1 (High)`, `Question`) and the markers as they are, because the author's skill looks for them. End every comment with `<!-- pr-review -->` (see `review-protocol.md`).

## Inline comment

```markdown
**[P1 (High)] Passing an empty array raises an exception**

When `items` is empty, `items[0]` raises `IndexError`.
`load_config()` can pass an empty array, so this can actually happen.

Returning early when it is empty looks like a good fix.

<!-- pr-review -->
```

For a question, start with `**[Question] ...**`.

## Summary

The review body that goes with the inline comments:

```markdown
## Review result

| Priority | Count |
|---|---|
| P0 | 0 |
| P1 | 1 |
| P2 | 2 |
| P3 | 0 |
| Question | 1 |

(Overall impressions in 2–3 sentences. Good points may be mentioned too.)

### Merge conditions
- P0 must be fixed. P1 should be fixed as a rule; to defer one, reply in its thread with the reason and the issue URL
- P2: fix it, or create an issue and reply in its thread with the URL
- P3 is optional. To decline one, reply in its thread with the reason
- Answer each Question in its thread

<!-- pr-review -->
```

## Review with no findings

Always post a review, even with no findings. The body is only "No findings" and a short impression, without the table. Put the completion marker before `<!-- pr-review -->`:

```markdown
No findings. (A short impression.)

<!-- review-complete -->
<!-- pr-review -->
```

When the author and the reviewer are the same account, `issue-to-pr` takes this marker as "review finished, nothing to fix", because with no threads there is nothing to resolve. Never put it on a review with findings or questions.

## Replies and records

- **Fix confirmed**: say which commit fixed it, e.g. "Confirmed (fixed in abc1234).", then resolve the thread.
- **Fix not sufficient, or not convinced**: give the concrete reason and leave the thread open.
- **Approve** (different account only): a short record that the merge conditions are met, with the head SHA.
- **Before merging** (`--merge` only): a short PR comment that all conditions are met, so the history can be followed later.
