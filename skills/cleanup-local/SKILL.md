---
name: cleanup-local
description: Clean up after GitHub PRs merge by pruning remote-tracking refs, removing merged worktrees and branches and stale agent fetch refs, and optionally fast-forwarding the main checkout. Use pr-review for merging.
---

# cleanup-local

Run when the user requests local cleanup or as the final step of a requested merge in `orchestrate-issue`.

## Arguments

- Optional `OWNER/REPO`, otherwise the repository of the current checkout.
- Optional `--pull` to fast-forward the main checkout.
- Optional `--keep-worktrees` to keep every worktree and the branches they hold.

## Workflow

1. **Confirm the target.** Verify which remote points to the target GitHub repository and find its default branch and the main checkout. Ask if the target or remote is unclear, because PR numbers and branch names can repeat across repositories. Read [the commands and GitHub REST lookups](references/commands.md) before running cleanup.
2. **Prune.** Run the branch-only `git fetch --prune` in the reference against the verified remote. Record the pruned remote-tracking refs and their previous SHAs. Stop if the fetch fails, because upstream state is then unverified. Keep tags and remote branches outside this cleanup.
3. **Clean up merged worktrees before deleting branches.** A branch checkout qualifies only if it passes the upstream and merged PR checks in step 4. A detached checkout qualifies only if its HEAD exactly matches a merged PR's head SHA in the target repository.
   - Keep every worktree with `--keep-worktrees`. Otherwise keep the main worktree, the one containing the invoking session, and any worktree containing another registered worktree. Keep locked worktrees because another session may be using them, and worktrees with nonempty `git status --porcelain --untracked-files=all` because they may hold unfinished work. Report each reason for skipping.
   - Before removal, read the repository's `AGENTS.md` and `CLAUDE.md` and run any documented worktree teardown from the candidate worktree. If teardown fails, keep the checkout so its resources can still be found, and report the failure.
   - Recheck eligibility and use `git worktree remove` without `--force`, so Git can refuse unsafe removal. Ignored files go with a removed worktree, even if they exist only there. The merged work is recorded in Git, and keeping worktrees because they contain ignored files would leave ordinary dependency installs behind.
4. **Clean up local branches.** Delete a local branch only if all of these checks pass:
   - After pruning, its upstream is marked `[gone]` and its source branch is absent from the verified remote. Keep branches without an upstream or whose upstream is on a different remote.
   - GitHub confirms a merged PR in the target repository with the same head branch name and the target repository as the head repository. The local SHA must equal that PR's head SHA, because a branch can receive more commits after its PR merges. Use the PR state and head SHA for merge, squash and rebase merges.
   - The branch is outside every worktree, including the current checkout. Recheck immediately before deleting because the worktree check and deletion are separate. Git can guard the SHA atomically, but another session can still check out the branch between the two operations.
5. **Clean up private fetch refs.** Consider exact `refs/agent-skills/<skill>/<number>/<run-id>` refs attributable to the target repository. Delete one only if GitHub confirms issue or PR `<number>` is closed and each worktree HEAD that the ref keeps reachable is also reachable from another current ref. Recompute reachability for each deletion, because two candidates may protect the same worktree and the last one must be kept.
6. **Check the main checkout.** With `--pull`, run `git pull --ff-only` only when the main checkout is on the default branch, `git status --porcelain --untracked-files=all` is empty, and the incoming tree will preserve ignored local files. This preserves the user's work in a shared checkout. If a check fails or the pull cannot fast-forward, report the reason. Without `--pull`, leave the checkout untouched and report how many commits its HEAD is behind the remote default branch.

For steps 4 and 5 use `git update-ref --no-deref -d <ref> <checked SHA>`. Keep a ref if its SHA changed or any required check is inconclusive, and report the reason. Use full ref names and direct refs so the command deletes only the ref you checked.

## Report

- Each removed worktree by path and HEAD SHA, and each retained worktree by path and reason, including any failed teardown or removal.
- Each deleted ref by name and SHA, and each retained branch or private ref with the reason.
- The main checkout's branch (or detached state), HEAD and behind count before and after, including the pull result or why it was skipped. Report unknown values and any failed checks.
