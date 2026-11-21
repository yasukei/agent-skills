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
- Files ignored by `.gitignore` are removed with the worktree, on purpose. Git does not count them as changes, and they are not part of the repository by design: dependencies, build output, caches, test logs, or a copy of a local file such as `.env` whose original stays in the main checkout. A file that should have been committed but is ignored is an implementation or review miss, to be caught before the merge, not by keeping worktrees.
- The local branch is deleted only when its tip is the merged PR's head SHA and no worktree has it checked out. A squash or rebase merge makes `git branch -d` refuse, so delete it with `git update-ref -d refs/heads/<branch> <head SHA>`: Git checks the SHA in the same step, so a branch that moved after the check is kept. Unlike `git branch -D`, `update-ref` does not refuse a branch checked out elsewhere, so check `git worktree list --porcelain` first. Otherwise the branch is in use or has commits that are not in the PR, and it is kept.
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
