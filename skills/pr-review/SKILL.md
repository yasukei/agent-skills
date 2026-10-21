---
name: "pr-review"
description: Review a GitHub PR as the reviewer, post prioritized (P0–P3, Question) comments, then monitor it to check fixes, resolve threads and decide whether it can be merged. Merges only with `--merge`. Use when given a PR to review (e.g. 「レビューして」「PRを見て」), an issue whose PR to review once it exists (「このissueのPRをレビューして」), or when asked to check responses to review comments or whether a PR can be merged. Never changes code. Not for implementing or answering reviews as the author (use issue-to-pr), nor for reviewing prose-only documents.
---

# pr-review

Review a PR, post the findings on it, monitor the author's responses, and decide whether it can be merged. With `--merge`, merge once the conditions are met.

The role is **reviewer**, not author. Do not fix code, commit, push, or create issues on the author's behalf. The author does the work; this skill points out, checks and decides (and merges with `--merge`). Keeping the roles apart keeps the review independent.

When unsure, ask the user in chat, not on the PR. Stopping to ask beats going on unsure.

## Workflow

0. (When given an issue) wait until its PR is created
1. Prepare: gather information about the PR and the repository
2. Review: read the diff and collect findings
3. Post: post the inline comments and the summary as one review
4. Monitor: wait for new commits and replies, check them and resolve threads
5. Decide: check every merge condition. Merge with `--merge`; otherwise report and stop

Read these when the step needs them:

- `references/review-protocol.md`: the contract with `issue-to-pr` (markers, priority labels and what the reviewer accepts for each, replies, completion signals, the rules that keep the signals reliable). Read it before reviewing.
- `references/review-guidelines.md`: what to look at and how to set priorities. Read it before reviewing.
- `references/comment-format.md`: formats of inline comments, the summary, the no-findings review and replies.
- `references/monitoring.md`: how to receive updates (event subscription or polling) and when to stop.
- `references/github-commands.md`: commands for each step. If `gh` fails with `HTTP 403` saying GraphQL is not available, use the REST commands there.

## Merging (`--merge`)

- Merge, once the conditions in step 5 are met, only when the arguments contain `--merge` or the user explicitly asks for the merge (e.g. "review and merge it").
- Otherwise, report "ready to merge" when the conditions are met and stop, without merging or deleting the branch. "Review this", "look at the PR" and "check whether it can be merged" are not requests to merge.
- When in doubt, do not merge: it is hard to undo.

## Language

- Comments posted on the PR follow the language of the repository's recent PR descriptions and review comments; if there are none, use the user's language.
- Chat reports and questions use the user's language, even when the PR comments are in another language. Finding titles may be quoted as they are.

## 0. When given an issue: wait for its PR

When given an issue number or URL instead of a PR, monitor until the PR for that issue is created, then continue from step 1. Read "Waiting for a PR from an issue" in `references/monitoring.md` for how to find the PR, the interval, drafts, several candidates and when to stop.

Use the issue during the review too: check that the PR meets the issue's requirements and has no unrelated changes.

## 1. Prepare

- Get the PR description, base branch, head SHA, draft state and CI state (`gh pr view`).
- Get the diff (`gh pr diff`) and read the surrounding code as needed; the diff alone hides broken callers and invariants.
- Check the repository's conventions: `CLAUDE.md`, `CONTRIBUTING.md`, templates under `.github/`, linter and formatter settings. They take precedence over general review criteria.
- Decide the comment language (see "Language").
- If the PR is a draft, or already merged or closed, ask the user before reviewing.

## 2. Review

Read `references/review-guidelines.md` before starting. In short:

- Point out only real problems. Do not invent findings; if there is no problem, "no findings" is the correct result. Padding buries the findings that matter.
- Do not point out what linters or formatters catch.
- For each finding, write what the problem is, why (which input or situation causes what), and what to do.
- Check that the PR description does not contradict the implementation (see step 5).
- Label each finding with a priority (`P0 (Critical)` to `P3 (Low)`, or `Question`) as defined in `references/review-protocol.md`. Every finding thread, `Question` included, must be resolved in the end.

## 3. Post

Post the inline comments and the summary as **one review** with the event `COMMENT`, so the author gets one notification. Formats are in `references/comment-format.md`.

- Use `COMMENT`: when the author and the reviewer are the same account, Approve and Request changes are not available. With different accounts, Approve is posted later (step 5).
- Put each finding as an inline comment on its line. A finding not tied to a line (a contradiction with the PR description, the layout of a whole file) goes on the most related changed line or as a file-level comment, so it becomes a thread that can be resolved; plain PR comments cannot.
- A `suggestion` block is fine for a short, clear fix. It is a proposal the author can accept; this skill still does not change the code.
- **End every comment this skill posts** (inline, summary, replies) with `<!-- pr-review -->`. The author may be the same account, so the marker is how both sides tell comments apart; treat comments without it as the author's (or another reviewer's).
- **Always post a review, even with no findings**, with the completion marker `<!-- review-complete -->` before `<!-- pr-review -->`. Never put the completion marker on a review with findings or questions.

## 4. Monitor

After posting, wait for updates as described in `references/monitoring.md` (event subscription with a 15-minute poll, or a 15-minute poll alone), and check the whole PR state each time.

### On new commits

- Read the diff from the last checked SHA to the new one.
- Check that unresolved findings are fixed and that the fixes add no new problems.
- Post new problems as new findings with priorities, as one review again. **Post them before resolving existing threads**: with the same account, `issue-to-pr` treats "all threads resolved" as done, so resolving first could end its monitoring before the new findings arrive.
- If an existing finding's fix is sound, reply with the commit that fixed it, then resolve the thread. If not, reply with the reason and leave it open.

### On replies in threads

Handle each reply as in "Replies" in `references/review-protocol.md`. Also: a `P0` cannot be deferred, so reply saying so and leave the thread open; never create the deferral issue yourself; ask the user when you cannot judge a decline.

Resolve only threads this skill opened (with the marker). Do not touch other reviewers' threads.

## 5. Decide whether it can be merged

The PR can be merged when all of these hold:

1. Every finding thread this skill opened is resolved (deferred ones too, after checking the issue).
2. No other reviewer's thread is unresolved and no Request changes remains. If one does, do not merge; ask the user.
3. All CI checks pass. Wait for pending checks to finish.
4. No conflicts, and branch protection rules (required approvals, etc.) are met. A required approval may be met by the Approve below.
5. The PR is not a draft.
6. **The PR description matches the implementation.** With a squash merge it becomes the commit message, so a description left stale by review changes leaves a wrong record. If it contradicts the implementation, post a new finding (usually P2; P1 if it misleads about behavior or compatibility) and wait for the update.
7. The head SHA at merge time is the last one you checked, so unchecked commits are never merged.

### Approve

When the PR author and the account running this skill differ, post an Approve review (a short record that the conditions are met, with the marker) once every condition except 4 is met, **whether or not `--merge` was given**: `issue-to-pr` takes the latest non-author Approve as its completion signal, and it may also satisfy a required approval in condition 4. On the same account, Approve is impossible; all threads resolved (or the no-findings review with the completion marker) is the signal instead.

### Without `--merge`

Report in chat that the PR can be merged and stop. Unsubscribe from PR events if subscribed.

### With `--merge`

1. Check which merge methods the repository allows.
2. Infer the method used for existing merged PRs from the base branch history and use the same one.
3. If it cannot be inferred, choose from the allowed methods in the order merge → squash → rebase.

Before merging, leave a short PR comment (with the marker) that all conditions are met, so the history can be followed later. Merge pinned to the checked head SHA, then delete the branch (or leave it to the repository's automatic deletion). Unsubscribe from PR events if subscribed. If the merge fails (branch protection, missing approvals, etc.), do not work around it; report to the user.

## Reporting to the user

Report briefly in chat at each milestone, in the user's language:

- After posting the review: the count per priority and the main findings
- When a decision is needed while monitoring: what it is about and which options you are weighing
- After merging, after deciding the PR can be merged (without `--merge`), or when monitoring stops: the result and what remains
