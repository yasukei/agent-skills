# Cleanup after a merge

Read when a PR has been merged. The agents keep their checkouts on exit. Use `cleanup-local` to remove merged worktrees and run any repository-specific teardown in them. This also removes eligible local branches and stale agent fetch refs and avoids another implementer run after the merge.

## Order

1. Confirm the PR is merged ("PR state" in `github-commands.md`) and post the observations comment (`observations.md`). Its line lookups read Git objects, so they work even if a worktree is already gone.
2. For one issue, run the installed `cleanup-local` skill yourself with `OWNER/REPO --pull` after posting observations. Run commands from the target repository's main checkout and give `cleanup-local` the actual session directory for its worktree checks. Pass `--keep-worktrees` when supplied to preserve worktrees and the branches they hold while still allowing eligible ref cleanup and a fast-forward.
3. For several issues, defer step 2 until the final report, and run cleanup once per target checkout with a confirmed merge, even when the batch stops early. Agents branch from the remote default branch, so a batch needs no intervening local pull.

Keep the Codex run files in your scratch directory (`codex.md`). They are the record of each run, and removing them is the user's call.

## When cleanup does not happen

An unmerged PR keeps its worktrees. After a merge, `cleanup-local` may keep a worktree because of `--keep-worktrees`, a held lock or guard, local changes, a nested worktree, the current session or main checkout, inconclusive eligibility, or failed teardown or removal. Report the kept path and reason, including an unavailable cleanup skill or a sandbox denial, so the user can decide. Report deleted worktrees and refs with their SHAs, retained refs with reasons, and the main checkout's before and after state.
