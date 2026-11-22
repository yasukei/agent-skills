# Cleanup after a merge

Read when a PR has been merged. After a merge, the agents' worktrees hold little that is not elsewhere: the commits are on GitHub, and the agents' conversations are stored by the agents themselves (Codex sessions, Claude Code transcripts), not in the worktree. Leftover worktrees pile up, and a review checkout inside the main worktree holds PR code that test runners there can pick up. With `--keep-worktrees`, skip the two worktree removal handoffs and still run local ref cleanup, which protects branches and fetch refs in use.

## What is removed, and by whom

Each agent removes its own worktree, so you keep out of hands-on work and the agent that knows the checkout verifies it. Both skills remove a worktree only when the user requests cleanup and its changes are preserved; the handoff carries that request.

| Agent | Removes | When |
|---|---|---|
| Reviewer | Its detached review worktree | In the merge handoff, right after a successful merge ("Reviewer: merge" in `handoffs.md`) |
| Implementer | Its worktree | After you confirmed the merge, in one resumed run ("Implementer: cleanup" in `handoffs.md`) |

- Only after a merge. Confirm `merged` is `true` ("PR state" in `github-commands.md`) before sending the implementer's cleanup. An unmerged PR keeps its worktrees, because a later session needs them to continue.
- A worktree is removed with `git worktree remove` and never with `--force`. Git refuses when there are uncommitted changes or untracked files that are not ignored, so a worktree with possible unfinished work is kept and reported instead of lost.
- Files ignored by `.gitignore` are removed with the worktree, including any that exist only there and cannot be recreated (e.g. local settings or data an agent created or edited in the worktree). This data loss is accepted by design; do not check for or keep ignored files. After the merge, everything the repository needs has been committed, reviewed and merged, and ignored files are outside the repository by definition. An ignored file that should have been committed is an implementation or review miss, to be caught before the merge, not by keeping worktrees. Keeping every worktree with ignored files would also stop cleanup in any repository with installed dependencies.
- Keep the Codex run files in your scratch directory (`codex.md`). They are the record of each run, and removing them is the user's call.

## Order

1. The reviewer merges and removes its review worktree, in the same handoff.
2. You confirm the merge and post the observations comment (`observations.md`). Its line lookups read Git objects, so they work from the target repository's checkout after the worktrees are gone.
3. You resume the implementer once with the cleanup handoff.
4. As the final cleanup step, run the installed `cleanup-local` skill yourself with `OWNER/REPO --pull` in the target repository's main checkout, after the agents have finished the applicable worktree handoffs. This is mechanical cleanup following the requested merge. With several issues, finish each merged issue's worktree handoffs before starting the next one. Before the final report, run `cleanup-local --pull` once for each target checkout where a PR merged in this run, including when the batch stops early. Report deleted refs by name and SHA, including local branches, kept refs with reasons, and the main checkout's before and after state.

## When cleanup does not happen

Leave the agents' worktrees to them and report any kept path and reason, so the user can decide.

- An agent refuses or fails, e.g. a worktree with leftovers or a sandbox denial.
- An agent cannot be resumed (its Codex thread or subagent is gone).
- A worktree belongs to an agent of an earlier session ("Existing PR" in `handoffs.md`). The current agents remove only the checkouts they used.
- The PR was not merged through this session, e.g. the user merges it by hand later.

If the local cleanup skill is unavailable or a check prevents cleanup, report the affected refs or checkout and the reason.
