# Exit conditions

Read this before monitoring with `--watch`, when deciding whether monitoring can stop, and before reporting the one-pass result without `--watch`. `scripts/pr_status.sh <PR number>` computes the decision as `verdict`; the completion signals themselves are defined in `review-protocol.md`.

## Can this environment monitor?

Check this when `--watch` is given, before starting the work. Monitoring is supported only if something wakes this session again after the reply ends, because the checks are 5–10 minutes apart and reviews take longer than one reply:

- **Supported**: a PR event subscription (e.g. Claude Code on the web), or a scheduled wakeup or loop the agent can set up itself (e.g. `/loop`, `ScheduleWakeup`, a trigger or a cron tool the session offers).
- **Not supported**: nothing can restart the session after the reply ends. For example, Codex CLI has no built-in way to run on a schedule; it runs again only when started from outside (e.g. `codex exec` from cron). A `sleep` loop inside one reply does not count: commands time out and the reply ends long before a review arrives.

If it is not supported, say so at the start, before doing the work, so the user does not wait for monitoring that will not happen. Then do the one pass as without `--watch`. Example:

```
--watch is not supported in this environment: nothing can wake this session after the reply ends, so the PR will not be monitored.
I will open the PR and report its state once. To handle reviews later, ask again (e.g. "handle the review of PR #51"), or run this skill periodically from outside (e.g. cron).
```

## `verdict.status`

Monitoring ends when `verdict.done` is `true` (`status` is `ready`, `merged` or `closed`), or after 60 minutes without reviewer activity ("Monitoring schedule"). Otherwise keep monitoring, except for an explicit completion without a marker (below).

| `verdict.status` | State | Next step |
|---|---|---|
| `merged` / `closed` | The PR was merged or closed | Stop and report |
| `ci_failing` | CI is failing | Handle it as in "When CI fails" in `handling-updates.md` |
| `ci_pending` | CI is running | Wait (every 30–60 s) |
| `conflicting` | Conflicts with the base branch | Handle it as in "When the PR conflicts" in `handling-updates.md` |
| `mergeable_unknown` | GitHub is still computing mergeability (e.g. right after a push) | Wait (every 30–60 s) |
| `waiting_for_review` | No reviewer activity yet | Wait on the review schedule (below) |
| `review_in_progress` | Under review (unresolved findings, waiting for Approve, or waiting for the completion signal) | Handle the findings and wait on the review schedule (below) |
| `ready` | Review is complete and all CI checks pass | Stop and report |

`ci.summary` of `none` (no checks at all) counts as passing. If the repository has CI configured but the summary is `none`, the checks may not be registered yet right after a push; wait a little and look again.

## Monitoring schedule

The same schedule is used by `pr-review`, so the two sides check each other at a similar pace.

- **Time counts from the start of monitoring** (when the PR is opened, or the first check of a `--watch` run on an existing PR), and **restarts from zero at each new reviewer activity** ("Reviewer activity" below: a review, a thread comment or a PR comment without the `<!-- issue-to-pr -->` marker, or a thread the reviewer resolved). Your own replies and pushes do not restart it.
- **Waiting for the reviewer** (`waiting_for_review`, and `review_in_progress` after you have replied and pushed): check **every 5 minutes** for the first 20 minutes, then **every 10 minutes** until 60 minutes.
- **CI and mergeability** (`ci_pending`, `mergeable_unknown`) are not bound to that schedule: you are checking a machine, not waiting for a person, so check every 30–60 s.
- **With a PR event subscription**, handle each event as soon as it arrives, without waiting for the next scheduled check. Keep the scheduled checks as well, because some events (new pushes, CI success, conflicts) may not arrive.
- **After 60 minutes without reviewer activity**, if `verdict.done` is still `false`, stop and report as in "When monitoring stops before completion" below, so a session is not held while nobody is reviewing.

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

**Without `--watch`** (one pass):

- After opening a new PR: the PR URL, and that the PR is not monitored (to handle CI and reviews later, ask again or use `--watch`). There is no need to wait for CI.
- After handling CI failures or review comments: the PR URL, the current `verdict.status`, what remains (e.g. CI running, waiting for review, unresolved threads) and how to continue (ask again, or use `--watch`). Report "ready to merge" only if `verdict.status` is `ready`; otherwise say that the PR is not monitored.

**On `ready`**, report in chat:

- The PR URL and that it is ready to merge.
- A summary of the review comments handled: fixed / declined with a reason / answered.
- What happened in CI and how it was handled, if anything.

**On `merged` or `closed`**, say so and summarize what was handled until then.

**When the user explicitly asks to stop monitoring**, stop. Say that this is not an end by review completion, and give the current `verdict` and what remains.

**When monitoring stops before completion** with `--watch` (60 minutes without reviewer activity, a session time limit, or a wake-up mechanism that stops working), never report "ready to merge". Say that the work is not complete, that monitoring stops here, and how to resume. Example:

```
Stopping the monitoring of PR #51 here. It is not complete yet.

- State: waiting for review (CI passes, no reviews or comments yet)
- No reviewer activity for 60 minutes, so monitoring stops
- To resume, ask "handle the review of PR #51" once a review has been posted
```
