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

- `references/review-protocol.md`: the contract with `issue-to-pr` (markers, priority labels, replies, completion signals). Read it before reviewing.
- `references/review-guidelines.md`: what to look at and how to set priorities. Read it before reviewing.
- `references/comment-format.md`: how to post the review, and the formats of inline comments, the summary, the no-findings review and replies. Read it before posting.
- `references/monitoring.md`: how to receive updates, how to check new commits and replies, and when to stop. Read it before monitoring.
- `references/merging.md`: the merge conditions in detail, Approve, and the merge procedure. Read it before deciding (step 5).
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

- Get the PR description, base branch, head SHA, draft state, CI state and diff, and read the surrounding code as needed; the diff alone hides broken callers and invariants.
- The repository's conventions (`CLAUDE.md`, `CONTRIBUTING.md`, templates under `.github/`, linter and formatter settings) take precedence over general review criteria.
- Decide the comment language (see "Language").
- If the PR is a draft, or already merged or closed, ask the user before reviewing.

## 2. Review

Read `references/review-guidelines.md` before starting. Point out only real problems, with what, why and what to do; if there is none, "no findings" is the correct result. Padding buries the findings that matter.
Label each finding with a priority (`P0 (Critical)` to `P3 (Low)`, or `Question`) as defined in `references/review-protocol.md`. Every finding thread, `Question` included, must be resolved in the end.

## 3. Post

Post the inline comments and the summary as **one review** with the event `COMMENT`, as in "Posting the review" in `references/comment-format.md`.

- **End every comment this skill posts** with `<!-- pr-review -->`; treat comments without it as the author's (or another reviewer's), because the author may be the same account.
- **Always post a review, even with no findings**, with `<!-- review-complete -->` before `<!-- pr-review -->`. Never put the completion marker on a review with findings or questions.

## 4. Monitor

Wait for updates as in `references/monitoring.md` (event subscription with a 15-minute poll, or a 15-minute poll alone), check the whole PR state each time, and handle new commits and replies as it describes. In short:

- Post new findings as one review **before resolving existing threads**: with the same account, `issue-to-pr` treats "all threads resolved" as done.
- Resolve a thread only after confirming its fix and replying with the fixing commit, and only threads this skill opened.
- A `P0` cannot be deferred. Never create the deferral issue yourself; ask the user when you cannot judge a decline.

## 5. Decide whether it can be merged

Read `references/merging.md`. In short, the PR can be merged when every finding thread this skill opened is resolved, no other reviewer's thread or Request changes remains, all CI checks pass, there are no conflicts and branch protection is met, it is not a draft, its description matches the implementation, and its head SHA is the last one you checked.

- When the author is a different account, post an Approve once every condition except conflicts and branch protection is met, **whether or not `--merge` was given**: it is `issue-to-pr`'s completion signal.
- Without `--merge`, report in chat that it can be merged and stop. With `--merge`, merge as `references/merging.md` describes; if the merge fails, do not work around it, report to the user.

## Reporting to the user

Report briefly in chat at each milestone, in the user's language:

- After posting the review: the count per priority and the main findings
- When a decision is needed while monitoring: what it is about and which options you are weighing
- After merging, after deciding the PR can be merged (without `--merge`), or when monitoring stops: the result and what remains
