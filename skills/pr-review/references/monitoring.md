# Finding a PR and checking responses

Read this before looking up an issue's PR (step 0 in SKILL.md) or checking new commits and replies (step 4).

## Checking new commits and replies (step 4)

### On new commits

- Read the diff from the last checked SHA to the new one. A re-check takes it from the `commit_id` of the latest review it owns: a review with the `<!-- pr-review -->` marker whose `agent-signature` has this run's `agent` and `session` (neither `unknown`), or the `session` the user agreed to resume ("Thread ownership" in `review-protocol.md`). Every review, Approve included, pins `commit_id` to the SHA it checked ("Posting a review" in `github-commands.md`). Skip reviews from another agent, another session or with no signature: another reviewer's newer review must not move this reviewer's baseline past commits it never checked. If no review qualifies, review the whole diff again.
- Check that unresolved findings are fixed and that the fixes add no new problems.
- Post new problems as new findings with priorities, as one review again. **Post them before resolving existing threads** because a review of the current head with all threads resolved can signal completion on the same account.
- If an existing finding's fix is sound, reply with the commit that fixed it, then resolve the thread. If not, reply with the reason and leave it open.
- When a re-check clears a new head, post a new completion signal pinned to the SHA you checked. On the same account, post a no-findings review with `<!-- review-complete -->` after confirming any outstanding fixes and resolving their threads. On a different account, post a fresh Approve once the conditions in "Approve" in `merging.md` are met.

### On replies in threads

Handle each reply as in "Replies" in `review-protocol.md`. Also: a `P0` cannot be deferred, so reply saying so and leave the thread open; never create the deferral issue yourself; ask the user when you cannot judge a decline.

Resolve only threads this run owns, as "Thread ownership" in `review-protocol.md` decides from the root comment's marker and signature: resolve its own, ask the user about a thread from a different or unknown session (resolve only after a yes), and never touch another agent's or another reviewer's threads.

## Finding a PR from an issue (step 0)

- Look once for PRs linked to the issue (PRs that will close it with `Closes #123` etc., and PRs referencing it in its timeline). See "Finding the PR for an issue" in `github-commands.md`.
- If there are several open candidates, ask the user which to review.
- If there is no PR or the selected PR is a draft, report that and end.
- If a PR is ready for review, say which PR you will review, then start the review.
