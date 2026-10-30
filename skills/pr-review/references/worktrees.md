# Isolated review (`--worktree`)

Read once the target PR is identified, before local review or tests. When starting from an issue, wait to find its PR as usual; do not create a speculative review checkout. This option does not authorize code fixes, commits, pushes, monitoring or merging.

## Prepare a detached checkout

- Record the target `OWNER/REPO`, the original checkout's absolute path and the installed skill's absolute directory. Run skill helpers from that absolute directory and use explicit repository arguments for GitHub operations, so neither a missing helper nor a fork remote changes the operation's target.
- Read repository instructions and any worktree location convention. Otherwise prefer a sibling directory such as `<repo>-worktrees/pr-<number>-review`, outside the original checkout; honor a user-specified path. Check write permissions and request access if necessary. If setup fails, stop and report it instead of silently reviewing the original checkout's code.
- Inspect `git worktree list --porcelain` and the destination first. Reuse only a worktree whose Git common directory matches this repository and whose purpose is this PR's review. Check that it is detached and available; a matching path alone does not establish ownership.
- Check `git -C "$worktree" status --porcelain --untracked-files=all`. If dirty or in use by another session, preserve it and ask before using it. Do not stash, reset, clean or force checkout, and do not detach the author's branch. Choose another unused path if an unrelated destination exists.

Fetch through a remote verified to point to the PR's **base repository** (often `origin`). Its PR ref also covers fork PRs; fetching the author's branch from the base repository does not. The variables below are values already identified for this run. Choose a unique `fetch_ref`, such as `refs/agent-skills/pr-review/<number>/<unique-run-id>`, so concurrent fetches cannot replace the shared `FETCH_HEAD` between commands.

```bash
# REST works even when GraphQL is blocked. repo is OWNER/REPO.
head_sha=$(gh api "repos/$repo/pulls/$pr" --jq .head.sha)
git fetch --no-write-fetch-head "$base_remote" "refs/pull/$pr/head:$fetch_ref"
fetched_sha=$(git rev-parse "${fetch_ref}^{commit}")
```

Verify `fetched_sha` equals `head_sha`. If the PR advanced during preparation, refresh its metadata and fetch again before reviewing. If the ref or commit cannot be fetched, report it; do not substitute a similarly named local branch.

```bash
# New destination only; use the reuse rules above for an existing worktree.
git worktree add --detach "$worktree" "$head_sha"
git -C "$worktree" rev-parse HEAD
```

Confirm the checkout's HEAD is the fetched PR SHA before reading or running that code. Detached HEAD avoids taking the author's branch, since Git allows a branch in only one worktree. Leave the original checkout's branch and files in place, including uncommitted changes; fetches still update the shared Git object database.

## Review and follow-up checks

Set the working directory explicitly to the worktree for local review and tests; a `cd` may not persist between tool calls. Read repository instructions there, prepare dependencies as required and follow the repository's setup procedure for ignored files. Git does not copy them, and the original checkout must not be copied wholesale.

Use the PR's actual base and head for the diff, not the detached checkout's branch name. Keep the SHA you actually reviewed as the `commit_id` when posting comments and reviews (`github-commands.md`), so a concurrent push is not accidentally marked reviewed.

On each new head, whether with `--watch` or a later re-check:

1. Retain the last checked SHA as defined in `monitoring.md`; the checkout's HEAD alone is not the review baseline.
2. Refresh PR metadata and fetch and verify the head as above.
3. Confirm the review worktree is still detached, clean and available. If tests left changes or another session took it over, preserve the files and ask before reusing it, or create another unused detached worktree.
4. Use `git -C "$worktree" checkout --detach "$head_sha"` without force, verify HEAD, then inspect the new commits and run the relevant checks there before posting or resolving threads.

With `--merge`, retain the existing merge conditions and pin the merge to the last checked SHA. Perform remote branch deletion only as the merge procedure allows; do not switch or delete a local branch held by the author's worktree, or remove that worktree. Use the REST merge and remote deletion commands in `github-commands.md` if the CLI would try to change a local checkout. For a fork PR, branch deletion targets the head repository, never a same-named branch in the base repository.

## Report and resume

Keep the review worktree on exit, including after merging or a monitoring timeout, so a later request can reuse it. Report the PR URL, absolute worktree path and checked SHA. On resumption, verify its identity, status and the current PR head again; an existing directory is not proof that its code is current. Remove it only when the user requests cleanup and its changes have been preserved; never remove it forcibly.
