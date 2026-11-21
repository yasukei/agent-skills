# Cleanup after a merge

Read when a PR has been merged, unless the user gave `--keep-worktrees`. After a merge, the agents' worktrees hold little that is not elsewhere: the commits are on GitHub, and the agents' conversations are stored by the agents themselves (Codex sessions, Claude Code transcripts), not in the worktree. Leftover worktrees pile up, and a review checkout inside the main worktree holds PR code that test runners there can pick up.

## What is removed, and by whom

Each agent removes its own worktree, so you keep out of hands-on work and the agent that knows the checkout verifies it. Both skills remove a worktree only when the user requests cleanup and its changes are preserved; the handoff carries that request.

| Agent | Removes | When |
|---|---|---|
| Reviewer | Its detached review worktree | In the merge handoff, right after a successful merge ("Reviewer: merge" in `handoffs.md`) |
| Implementer | Its worktree, then its local branch | After you confirmed the merge, in one resumed run ("Implementer: cleanup" in `handoffs.md`) |

- Only after a merge. Confirm `merged` is `true` ("PR state" in `github-commands.md`) before sending the implementer's cleanup. An unmerged PR keeps its worktrees, because a later session needs them to continue.
- A worktree is removed with `git worktree remove` and never with `--force`. Git refuses when there are uncommitted changes or untracked files that are not ignored, so a worktree with possible unfinished work is kept and reported instead of lost.
- Files ignored by `.gitignore` are removed with the worktree, including any that exist only there and cannot be recreated (e.g. local settings or data an agent created or edited in the worktree). This data loss is accepted by design; do not check for or keep ignored files. After the merge, everything the repository needs has been committed, reviewed and merged, and ignored files are outside the repository by definition. An ignored file that should have been committed is an implementation or review miss, to be caught before the merge, not by keeping worktrees. Keeping every worktree with ignored files would also stop cleanup in any repository with installed dependencies.
- The local branch is deleted only when its tip is the merged PR's head SHA. A squash or rebase merge makes `git branch -d` refuse, so check the tip, then delete with `git branch -D <branch>`. Git still refuses a branch in use: checked out in any worktree, or used by a rebase or bisect in progress there. Then compare the SHA in its output (`Deleted branch <branch> (was <short SHA>).`) with the head SHA: if the branch moved between the check and the deletion, recreate it at once with `git branch <branch> <short SHA>` and report it. The commits stay in the object database, so nothing is lost. `git update-ref -d` with the expected SHA would check the SHA in the same step, but it skips Git's in-use checks and deletes a branch that a paused rebase in another worktree still uses.
- Keep the Codex run files in your scratch directory (`codex.md`). They are the record of each run, and removing them is the user's call.

## Order

1. The reviewer merges and removes its review worktree, in the same handoff.
2. You confirm the merge and post the observations comment (`observations.md`). Its line lookups read Git objects, so they work from the target repository's checkout after the worktrees are gone.
3. You resume the implementer once with the cleanup handoff.
4. With several issues, finish the cleanup before starting the next issue.

## When cleanup does not happen

Do not remove anything yourself; report the path and the reason in the final report, so the user can decide.

- An agent refuses or fails, e.g. a worktree with leftovers, a branch with extra commits, or a sandbox denial.
- An agent cannot be resumed (its Codex thread or subagent is gone).
- A worktree belongs to an agent of an earlier session ("Existing PR" in SKILL.md). The current agents remove only the checkouts they used.
- The PR was not merged through this session, e.g. the user merges it by hand later.
