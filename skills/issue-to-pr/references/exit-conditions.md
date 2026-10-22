# Exit conditions

Read this when deciding whether monitoring can stop. `scripts/pr_status.sh <PR number>` computes the decision as `verdict`; the completion signals themselves are defined in `review-protocol.md`.

## `verdict.status`

Monitoring ends when `verdict.done` is `true` (`status` is `ready`, `merged` or `closed`). Otherwise keep monitoring, except for an explicit completion without a marker (below).

| `verdict.status` | State | Next step |
|---|---|---|
| `merged` / `closed` | The PR was merged or closed | Stop and report |
| `ci_failing` | CI is failing | Handle it as in "When CI fails" in `handling-updates.md` |
| `ci_pending` | CI is running | Wait (every 30–60 s) |
| `conflicting` | Conflicts with the base branch | Handle it as in "When the PR conflicts" in `handling-updates.md` |
| `mergeable_unknown` | GitHub is still computing mergeability (e.g. right after a push) | Wait (every 30–60 s) |
| `waiting_for_review` | No reviewer activity yet | Wait (every 2–5 min) |
| `review_in_progress` | Under review (unresolved findings, waiting for Approve, or waiting for the completion signal) | Handle the findings and wait |
| `ready` | Review is complete and all CI checks pass | Stop and report |

`ci.summary` of `none` (no checks at all) counts as passing. If the repository has CI configured but the summary is `none`, the checks may not be registered yet right after a push; wait a little and look again.

## Reviewer activity

The author and the reviewer may be the same account, so reviewer activity is identified by the absence of the `<!-- issue-to-pr -->` marker, not by login (`review.activity`).

- **Counts**: reviews, review thread comments and PR comments without the marker.
- **Does not count**: comments this skill posted with the marker; the empty-body reviews GitHub creates automatically when replying to a thread; the PR description; the sub-agent review before the PR was created; posts by bots (Copilot, coverage reports, etc.).

The pre-PR sub-agent review and this skill's own replies never replace a review on the PR.

## When it is `ready`

The condition depends on whether the account that reviewed is different from the PR author (`review.mode`), because GitHub does not let you approve your own PR. Both modes also require all CI checks to pass and no conflicts.

**Different account** (`other_account`):

- The latest review from each account other than the author is Approve.
- Approve is the reviewer's decision, so it is fine to stop even if threads remain unresolved. Still reply to those threads first.

**Same account** (`same_account`):

- Having no reviewer on another account does not mean "reviewed by the same account". There must be actual reviewer activity as defined above.
- If the reviewer posted findings as threads: every reviewer thread is resolved. The reviewer resolves them; this skill does not.
- If there were no findings and no threads: a review or PR comment without the `<!-- issue-to-pr -->` marker contains the completion marker `<!-- review-complete -->`, and there is no reviewer activity (such as a question) after it (`review.explicitCompletion`).

A question or an intermediate comment alone is not completion. Examples:

| Reviewer activity | Verdict |
|---|---|
| None (no reviews, comments or threads) | `waiting_for_review`. Do not stop even if CI passes |
| Only this skill's replies and PR comments with the marker | `waiting_for_review` |
| A PR comment asking "Where is this function called from?" | `review_in_progress`. Answer and wait for the completion signal |
| An unresolved `[Question]` thread | `review_in_progress` |
| A review saying "No findings" with `<!-- review-complete -->` | `ready` |
| All finding threads resolved | `ready` |
| A PR comment with a question after the completion marker | `review_in_progress` |
| A completion marker, but a later unresolved thread with a repeated finding | `review_in_progress` |

**Explicit completion without a marker**: if the same-account reviewer is a human who wrote "review complete, no findings" without the completion marker, you may treat it as complete after confirming CI passes and there are no conflicts, even though `verdict` stays `review_in_progress`. This is the only case where you may stop against `verdict`. If the wording leaves any doubt, ask in chat.

Tell your own replies from reviewer comments by the `<!-- issue-to-pr -->` marker. A thread whose `lastCommentByMe` is `false` ends with a reviewer comment that may not have been answered yet. Do not mistake your own reply for a new finding, or a repeated finding for your own reply.

## Reports

**On `ready`**, report in chat:

- The PR URL and that it is ready to merge.
- A summary of the review comments handled: fixed / declined with a reason / answered.
- What happened in CI and how it was handled, if anything.

**On `merged` or `closed`**, say so and summarize what was handled until then.

**When the user explicitly asks to stop monitoring**, stop. Say that this is not an end by review completion, and give the current `verdict` and what remains.

**When the environment cannot keep monitoring** (no way to wake up after the reply ends, a session time limit, etc.), never report "ready to merge". Say that the work is not complete, that monitoring stops here, and how to resume. Example:

```
Stopping the monitoring of PR #51 here. It is not complete yet.

- State: waiting for review (CI passes, no reviews or comments yet)
- This environment cannot keep monitoring the PR after this reply ends
- To resume, ask "handle the review of PR #51" once a review has been posted
```
