---
name: cleanup-local
description: Clean up a local GitHub repository after PRs merge by pruning remote-tracking refs, removing merged branches and stale agent fetch refs, and optionally fast-forwarding the main checkout. Use issue-to-pr or pr-review for worktree removal and pr-review for merging.
---

# cleanup-local

Run when the user requests local cleanup or as the final step of a requested merge in `orchestrate-issue`.

## Arguments

- Optional `OWNER/REPO`, otherwise the repository of the current checkout.
- Optional `--pull` to fast-forward the main checkout.

## Workflow

1. **Confirm the target.** Verify which remote points to the target GitHub repository and find its default branch and the main checkout. Ask if the target or remote is unclear, because PR numbers and branch names can repeat across repositories. Read [the commands and GitHub REST lookups](references/commands.md) before running cleanup.
2. **Prune.** Run the branch-only `git fetch --prune` in the reference against the verified remote. Record the pruned remote-tracking refs and their previous SHAs. Stop if the fetch fails, because upstream state is then unverified. Keep tags and remote branches outside this cleanup.
3. **Clean up local branches.** Delete a local branch only if all of these checks pass:
   - After pruning, its upstream is marked `[gone]` and its source branch is absent from the verified remote. Keep branches without an upstream or whose upstream is on a different remote.
   - GitHub confirms a merged PR in the target repository with the same head branch name and the target repository as the head repository. The local SHA must equal that PR's head SHA, because a branch can receive more commits after its PR merges. Use the PR state and head SHA for merge, squash and rebase merges.
   - The branch is outside every worktree, including the current checkout. Recheck immediately before deleting because the worktree check and deletion are separate. Git can guard the SHA atomically, but another session can still check out the branch between the two operations.
4. **Clean up private fetch refs.** Consider exact `refs/agent-skills/<skill>/<number>/<run-id>` refs attributable to the target repository. Delete one only if GitHub confirms issue or PR `<number>` is closed and each worktree HEAD that the ref keeps reachable is also reachable from another current ref. Recompute reachability for each deletion, because two candidates may protect the same worktree and the last one must be kept.
5. **Check the main checkout.** With `--pull`, run `git pull --ff-only` only when the main checkout is on the default branch, `git status --porcelain --untracked-files=all` is empty, and the incoming tree will preserve ignored local files. This preserves the user's work in a shared checkout. If a check fails or the pull cannot fast-forward, report the reason. Without `--pull`, leave the checkout untouched and report how many commits its HEAD is behind the remote default branch.

For steps 3 and 4 use `git update-ref --no-deref -d <ref> <checked SHA>`. Keep a ref if its SHA changed or any required check is inconclusive, and report the reason. Use full ref names and direct refs so the command deletes only the ref you checked.

## Report

- Each deleted ref by name and SHA, and each retained branch or private ref with the reason.
- The main checkout's branch (or detached state), HEAD and behind count before and after, including the pull result or why it was skipped. Report unknown values and any failed checks.
