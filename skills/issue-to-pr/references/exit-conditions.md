# Reporting the PR verdict

Read this before reporting the result of a pass. `scripts/pr_status.sh <PR number>` reports the PR state as `verdict`. The completion signals are defined in `review-protocol.md`.

## `verdict.status`

| `verdict.status` | State | What to report |
|---|---|---|
| `merged` / `closed` | The PR was merged or closed | Report the result |
| `ci_failing` | CI is failing | Report failing checks and any action taken |
| `ci_pending` | CI is running | Report the current state |
| `conflicting` | Conflicts with the base branch | Report the conflict and any action taken |
| `mergeable_unknown` | GitHub is still computing mergeability (e.g. right after a push) | Report the current state |
| `waiting_for_review` | No reviewer activity yet | Report what remains |
| `review_in_progress` | Under review (unresolved findings, waiting for Approve, or waiting for the completion signal) | Report what remains after handling current findings |
| `ready` | Review is complete and all CI checks pass | Report the result |

The script treats `ci.summary` of `none` as passing. If CI is expected for the current head and its checks have yet to register, report that CI has not reported yet and leave merge readiness undetermined.

## Reviewer activity

The author and the reviewer may be the same account, so reviewer activity is identified by the absence of the `<!-- issue-to-pr -->` marker, not by login (`review.activity`).

- **Counts**: reviews, review thread comments and PR comments without the marker.
- **Does not count**: comments this skill posted with the marker; the empty-body reviews GitHub creates automatically when replying to a thread; the PR description; the sub-agent review before the PR was created; posts by bots (Copilot, coverage reports, etc.).

The pre-PR sub-agent review and this skill's own replies never replace a review on the PR.

## When it is `ready`

The condition depends on whether the account that reviewed is different from the PR author (`review.mode`), because GitHub does not let you approve your own PR. Both modes require passing CI, no conflicts, and a completion signal for the current PR head SHA. Each review applies only to the commit it was submitted for.

**Different account** (`other_account`):

- The latest review affecting approval status from each non-author reviewer is Approve on the current head. A stale approval leaves the verdict at `review_in_progress` until the reviewer approves the current head.
- An Approve can establish readiness with unresolved threads. Reply to those threads before reporting the verdict.

**Same account** (`same_account`):

- Having no reviewer on another account does not mean "reviewed by the same account". There must be actual reviewer activity as defined above.
- When there are finding threads, every reviewer thread is resolved and the latest submitted reviewer review is on the current head. GitHub reports thread resolution as a boolean, so the review's commit establishes which head was checked. The reviewer resolves the threads.
- On a PR this skill did not open, the author's earlier unmarked comments also look like reviewer activity. Check a `ready` verdict as in "PRs this skill did not open" in `handling-updates.md` before reporting it.
- When there are no finding threads, a review on the current head without the `<!-- issue-to-pr -->` marker contains `<!-- review-complete -->`, with no later reviewer activity (`review.explicitCompletion`). A plain PR comment carries no review commit and contributes only reviewer activity.

A question or an intermediate comment alone is not completion. Examples:

| Reviewer activity | Verdict |
|---|---|
| None (no reviews, comments or threads) | `waiting_for_review` |
| Only this skill's replies and PR comments with the marker | `waiting_for_review` |
| A PR comment asking "Where is this function called from?" | `review_in_progress`. Answer the question and report what remains |
| An unresolved `[Question]` thread | `review_in_progress` |
| A review on the current head saying "No findings" with `<!-- review-complete -->` | `ready` |
| A review on an older commit with `<!-- review-complete -->` | `review_in_progress` |
| All finding threads resolved and the latest reviewer review is on the current head | `ready` |
| All finding threads resolved after the reviewer last reviewed an older commit | `review_in_progress` |
| A PR comment with a question after the completion marker | `review_in_progress` |
| A completion marker, but a later unresolved thread with a repeated finding | `review_in_progress` |

**Explicit completion without a marker**: if the same-account reviewer is a human who wrote "review complete, no findings" without the completion marker, you may treat it as complete after confirming it applies to the current head SHA, CI passes and there are no conflicts, even though `verdict` stays `review_in_progress`. This is the only exception to requiring a verified `ready` verdict to report merge readiness. If the wording or the reviewed commit leaves any doubt, ask in chat.

Tell your own replies from reviewer comments by the `<!-- issue-to-pr -->` marker. A thread whose `lastCommentByMe` is `false` ends with a reviewer comment that may not have been answered yet. Do not mistake your own reply for a new finding, or a repeated finding for your own reply.

## Reports

- After opening a new PR, report its URL and end.
- After handling an existing PR, report its URL, current `verdict.status`, what you handled, and what remains (e.g. pending CI, outstanding review, unresolved threads). A later invocation can handle new updates.

**On verified `ready` or the same-account human reviewer exception**, report in chat:

- The PR URL and that it is ready to merge.
- A summary of the review comments handled: fixed / declined with a reason / answered.
- What happened in CI and how it was handled, if anything.

**On `merged` or `closed`**, say so and summarize what was handled until then.
