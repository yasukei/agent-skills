# Review protocol: issue-to-pr and pr-review

The contract between the author skill (`issue-to-pr`) and the reviewer skill (`pr-review`). Both skills ship an identical copy of this file as `references/review-protocol.md`; change both copies in the same PR, because each side relies on what the other posts.

## Roles

- **Author** (`issue-to-pr`): implements, pushes, and replies. Never merges, approves, resolves threads, or closes the PR or issue.
- **Reviewer** (`pr-review`): posts findings, checks the fixes, resolves its own threads, and decides whether the PR can be merged. Never changes the code.

## Markers

The author and the reviewer are often the same GitHub account, so login names cannot tell their comments apart. Each side appends a marker at the end of every comment it posts.

| Marker | Posted by | Meaning |
|---|---|---|
| `<!-- issue-to-pr -->` | Author, on every comment (thread replies, PR comments) | Written by the author |
| `<!-- pr-review -->` | Reviewer, on every comment (inline comments, review summaries, replies, Approve) | Written by the reviewer |
| `<!-- review-complete -->` | Reviewer, placed before `<!-- pr-review -->`, only on a review with no findings and no questions | Review finished, nothing to fix |

- The author treats every comment without `<!-- issue-to-pr -->` as the reviewer's (or someone else's), including the second and later comments in a thread: it is a new or repeated finding.
- The reviewer treats every comment without `<!-- pr-review -->` as the author's (or another reviewer's). It finds its own earlier findings by the marker and resolves only threads it opened.

## Findings and priority labels

The reviewer posts findings as inline review comments, so that each one is a thread that can be resolved (plain PR comments cannot). A finding not tied to a line goes on the most related changed line or as a file-level comment. Each finding starts with its label in bold, e.g. `**[P1 (High)] Empty array raises an exception**` or `**[Question] ...**`.

| Label | Meaning | What the reviewer accepts | What the author does |
|---|---|---|---|
| `P0 (Critical)` | Security issue, data corruption or loss, production outage, broken build or deploy | Fix in this PR. Deferring to an issue is not allowed | Must fix |
| `P1 (High)` | Clear bug, mismatch with the spec, missing tests for an important case | Fix in this PR as a rule. Deferring to an issue with a reason is allowed | Must fix |
| `P2 (Medium)` | Maintainability, performance, design | Fix, or defer to an issue | Fix as a rule |
| `P3 (Low)` | Naming, minor refactoring, preference | Optional. Declining with a reason is allowed | Judge whether it is valid; if declining, reply with the reason |
| `Question` | Intent or assumptions | An answer | Answer only; do not change code |

The author judges an unlabeled comment by its content.

Every finding thread, `Question` included, is eventually resolved, and only the reviewer resolves it. Resolving is how the reviewer says "I checked the response".

## Replies

The author replies to every reviewer comment in its thread, because a silent fix or a silent decline looks the same as an oversight:

- **Fixed**: what was changed and the commit SHA (e.g. "Added a null check (abc1234)").
- **Declined**: a concrete reason the reviewer can accept or argue with (e.g. "to match the existing behavior of X", "the issue requires Y").
- **Question**: the answer.

`issue-to-pr` does not defer findings to issues. Another author may, where the table allows it, by replying with the URL of an issue the author created; the reviewer never creates it.

The reviewer then:

- **On a fix**: reads the code. If the fix is sound, replies with the commit that fixed it and resolves the thread; if not, replies with the reason and leaves it open.
- **On a deferral**: checks that the issue exists and covers the finding. A `P0` cannot be deferred; for a `P1`, checks that the reason holds. Resolves if both are fine.
- **On a decline or "this is intended"**: resolves if convinced; otherwise replies with the reason.
- **On an answer to a `Question`**: resolves if the answer settles it. If the answer reveals a problem, posts it as a new finding and then resolves the `Question`.

## Completion signals

While the PR is open, the author treats the review as complete when CI passes, there is no conflict, and one of these signals is present:

| Accounts | Signal |
|---|---|
| Reviewer is a different account from the PR author | The latest review from each non-author account is **Approve** |
| Same account, findings were posted | **All reviewer threads are resolved** |
| Same account, no findings | A review or PR comment with **`<!-- review-complete -->`**, and no reviewer activity after it |

A question or an intermediate comment alone is never a completion signal.

## Rules the reviewer follows so the signals stay reliable

- Post findings as **one review** with the event `COMMENT`. The same account cannot Approve or Request changes on its own PR.
- Always post a review, even with no findings. With no findings, the body is a short "no findings" note with `<!-- review-complete -->` before `<!-- pr-review -->`. Never put the completion marker on a review that has findings or questions.
- When the author pushes, **post new findings before resolving existing threads.** With the same account, "all threads resolved" means done, so resolving first could end the author's monitoring before the new findings arrive.
- With a different account, post **Approve** once every merge condition except branch protection is met, whether or not `--merge` was given, because Approve is the author's completion signal.
