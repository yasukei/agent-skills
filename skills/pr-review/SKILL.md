---
name: "pr-review"
description: Review a GitHub PR as the reviewer, post prioritized (P0–P3, Question) comments, check fixes, resolve threads and decide whether it can be merged. Monitors the PR only with `--watch`, merges only with `--merge`. Use when given a PR to review (e.g. 「レビューして」「PRを見て」), an issue whose PR to review (「このissueのPRをレビューして」), or when asked to check responses to review comments or whether a PR can be merged. Never changes code. Not for implementing or answering reviews as the author (use issue-to-pr), nor for reviewing prose-only documents.
---

# pr-review

Review a PR, post findings, check the author's responses, and decide whether it can be merged. With `--watch`, keep monitoring; with `--merge`, merge once the conditions are met.

The role is **reviewer**: never fix code, commit, push, or create issues for the author; it points out, checks and decides. Keeping the roles apart keeps the review independent.

When unsure, ask the user in chat, not on the PR; asking beats going on unsure.

## Workflow

0. (When given an issue) find its PR; with `--watch`, wait until it is created
1. Prepare: gather information about the PR and the repository
2. Review: read the diff and collect findings
3. Post: post the inline comments and the summary as one review
4. Check: check new commits and replies and resolve threads; with `--watch`, keep monitoring
5. Decide: check every merge condition. Merge with `--merge`; otherwise report and stop

Read when the step needs them:

- `references/review-protocol.md` (the contract with `issue-to-pr`: markers, signature, ownership, priorities, replies, completion signals) and `references/review-guidelines.md` (what to look at): read both before reviewing.
- `references/comment-format.md`: how to post the review and format comments. Read it before posting.
- `references/monitoring.md`: checking new commits and replies, waiting for updates, and when to stop. Read it before step 0 or 4.
- `references/merging.md`: merge conditions, Approve and merging. Read it before step 5.
- `references/github-commands.md`: commands, with REST replacements for when `gh` fails with `HTTP 403` (no GraphQL).

## Monitoring (`--watch`)

Monitor (wait in steps 0 and 4) only when the arguments contain `--watch` or the user explicitly asks for it (e.g. 「監視して」「マージまで見て」); 「レビューして」「PRを見て」 alone are not. Monitoring keeps the session busy.

Without `--watch`, do one pass, report, and end:

- **First review**: post the review, then step 5 (merge conditions, Approve), and end.
- **Asked to re-check**: check fixes and replies once and resolve threads (step 4), then step 5, and end.
- **Given an issue with no PR yet**: report so and end.
- **`--merge`**: merge if every merge condition holds at that check; otherwise report which are missing and end.

With `--watch`, first check that something can wake this session after the reply ends ("Can this environment monitor?" in `references/monitoring.md`). If nothing can (e.g. Codex CLI), say at the start that `--watch` is unsupported here, and continue without it.

## Merging (`--merge`)

Merge, once the step 5 conditions are met, only when the arguments contain `--merge` or the user explicitly asks for it (e.g. "review and merge it"); 「レビューして」「PRを見て」 or "can it be merged?" are not. Otherwise report "ready to merge" and stop, without merging or deleting the branch. When in doubt, do not merge: it is hard to undo.

## Language

PR comments follow the language of the repository's recent PRs and reviews, else the user's. Chat uses the user's language; finding titles may be quoted as they are.

## 0. When given an issue: find its PR

Find the issue's PR as in "Waiting for a PR from an issue" in `references/monitoring.md`, then continue from step 1.
In the review, check that the PR meets the issue's requirements and has no unrelated changes.

## 1. Prepare

- Get the PR description, base branch, head SHA, draft and CI state and diff, and read the surrounding code; the diff alone hides broken callers and invariants.
- Read the repository's conventions (`CLAUDE.md`, `CONTRIBUTING.md`, `.github/` templates, linter settings); they override general review criteria.
- If the PR is a draft, or already merged or closed, ask the user before reviewing.

## 2. Review

Point out only real problems, with what, why and what to do (`references/review-guidelines.md`); if there is none, "no findings" is correct. Padding buries real findings.
Label each finding `P0 (Critical)` to `P3 (Low)`, or `Question`, as defined in `references/review-protocol.md`. Every finding thread, `Question` included, must be resolved in the end.

## 3. Post

Post the inline comments and the summary as **one review** with the event `COMMENT`, as in "Posting the review" in `references/comment-format.md`.

- **End every comment this skill posts** with the signature (`scripts/signature.sh`), then `<!-- pr-review -->`; comments without the marker are the author's or another reviewer's, who may share the account.
- **Always post a review, even with no findings**, with `<!-- review-complete -->` before `<!-- pr-review -->`. Never put the completion marker on a review with findings or questions.

## 4. Check responses, and monitor with `--watch`

Check new commits and replies as in `references/monitoring.md`; with `--watch`, wait for them as it says (events, plus checks every 5 min, then 10 min after 20 min, until 60 min without author activity), checking the whole PR state each time.

- Post new findings as one review **before resolving existing threads**: with the same account, `issue-to-pr` treats "all threads resolved" as done.
- Resolve only threads this run owns; ask the user about other sessions' ("Thread ownership" in `references/review-protocol.md`).
- A `P0` cannot be deferred. Ask the user when you cannot judge a decline.

## 5. Decide whether it can be merged

Read `references/merging.md`. In short: every finding thread this skill opened is resolved, no other reviewer's thread or Request changes remains, CI passes, no conflicts, branch protection is met, not a draft, the description matches the implementation, and the head SHA is the last one checked.

- When the author is a different account, post an Approve once every condition except conflicts and branch protection is met, **whether or not `--merge` was given**: it is `issue-to-pr`'s completion signal.
- Without `--merge`, report that it can be merged and stop. With `--merge`, merge as `references/merging.md` describes; if the merge fails, report it instead of working around it.

## Reporting to the user

Report briefly in chat:

- After posting the review: the count per priority and the main findings
- When a decision is needed: the options
- After merging, deciding it can be merged, a pass without `--watch`, or stopping monitoring: the result and what remains
