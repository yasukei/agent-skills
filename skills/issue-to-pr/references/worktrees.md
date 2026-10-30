# Isolated implementation (`--worktree`)

Read before changing files or branches when `--worktree` is requested. It changes the checkout used for the work, not the skill's review, monitoring or merge permissions.

## Select the checkout

- Record the target `OWNER/REPO`, the original checkout's absolute path and the installed skill's absolute directory before changing directories. Run helpers from that skill directory, because a target repository need not contain them. Use explicit repository arguments for GitHub operations so a fork remote cannot redirect them.
- Read the target repository's instructions and any worktree location convention. Otherwise prefer a sibling directory such as `<repo>-worktrees/issue-<number>`, outside the original checkout; honor a user-specified path. Check write permissions and request access if necessary. If creation fails, stop and report it rather than silently editing the original checkout.
- Inspect `git worktree list --porcelain`, local branches and the destination before creating anything. Reuse only a worktree for this repository and issue or PR: verify its Git common directory, branch and PR head repository. A matching directory name alone is not evidence.
- If the intended branch is held by the original checkout, report the conflict and ask how to proceed; do not switch that checkout or silently work there. This applies to both new issues and existing PRs.
- Check the candidate with `git -C "${worktree:?}" status --porcelain --untracked-files=all`. If dirty or in use by another session, preserve it and ask before using it; do not stash, reset, clean, overwrite or delete someone else's work. If an unrelated path exists, choose another unused path.
- Leave the original checkout's branch and files in place, including uncommitted changes. Worktrees share refs and objects, so fetches and the new branch are still visible in the repository. Do not use `--force` or `--ignore-other-worktrees`: Git's branch ownership protects concurrent work.

## New issue

Use the latest default branch of the target repository and the branch naming convention in `conventions.md`. The following variables are values already identified for this run; `base_remote` must point to the target repository (often `origin`), not an unrelated fork. Choose a unique `fetch_ref`, such as `refs/agent-skills/issue-to-pr/<number>/<unique-run-id>`, so parallel fetches cannot replace the shared `FETCH_HEAD` between commands.

```bash
# REST works even when GraphQL is blocked. repo is OWNER/REPO.
default_branch=$(gh api "repos/${repo:?}" --jq .default_branch)
git fetch --no-write-fetch-head "${base_remote:?}" "refs/heads/${default_branch:?}:${fetch_ref:?}"
base_sha=$(git rev-parse "${fetch_ref:?}^{commit}")
git worktree add -b "${branch:?}" "${worktree:?}" "${base_sha:?}"
```

If the branch already exists, inspect it and its registered worktree instead of recreating or resetting it. Reuse it only after confirming it belongs to this issue; ask if its purpose is unclear. Git cannot attach the same branch to two worktrees: use its verified, available worktree rather than detaching it from another checkout.

## Existing PR or review fixes

Continue the PR's head branch rather than creating a branch from the default branch, because fixes must update the existing PR.

```bash
gh api "repos/${repo:?}/pulls/${pr:?}" \
  --jq '{head_repo: .head.repo.full_name, head_ref: .head.ref, head_sha: .head.sha}'
# head_remote must point to head_repo, including for fork PRs.
git fetch --no-write-fetch-head "${head_remote:?}" "+refs/heads/${head_ref:?}:${fetch_ref:?}"
fetched_sha=$(git rev-parse "${fetch_ref:?}^{commit}")
```

Verify `fetched_sha` equals the API's `head_sha`; if it changed during preparation, refresh the metadata and fetch again. Stop if the head repository or branch is unavailable.
The leading `+` updates only this run's private `refs/agent-skills/issue-to-pr/...` fetch ref when a remote head is rewritten. Never use a local branch or another run's ref as `fetch_ref`; branch fast-forwards and the prohibition on force-pushes still apply.

- If the head branch is already checked out, inspect and reuse that worktree only under the checks above.
- If the local branch exists but is not checked out, attach it with `git worktree add "${worktree:?}" "${head_ref:?}"` after verifying its identity and history. If it does not exist, use `git worktree add -b "${head_ref:?}" "${worktree:?}" "${fetched_sha:?}"`.
- In a clean, verified worktree, fast-forward a behind branch with `git -C "${worktree:?}" merge --ff-only "${fetched_sha:?}"`. Inspect local commits ahead of the PR before continuing; if their ownership is unclear or history has diverged, ask instead of resetting or rebasing.
- Push explicitly to the verified head repository and head branch (for example, `git -C "${worktree:?}" push "${head_remote:?}" "HEAD:refs/heads/${head_ref:?}"`), so a fork PR receives the fixes.

## Work and resume

Shell variables and `cd` may not survive a tool call. Substitute literal absolute paths and verified values into each call, or initialize them in that call; all examples use `${variable:?}` to fail before Git runs if a value is missing or empty. In particular, `git -C ""` runs in the current checkout and must never be used as a fallback.

Set the working directory explicitly to the worktree for every implementation command, local check, commit and push. Read the repository instructions there and install dependencies as required. Ignored setup files are not copied by Git: follow the repository's setup procedure rather than copying secrets or the original checkout wholesale.

### Claude Code session directory

When available, call `EnterWorktree` with `path` set to the verified absolute worktree path after Git creates it; do not use `name`, which creates a different branch and checkout. This moves the session's working directory and write access, avoiding Bash's reset to the original project. Complete any permission prompt before proceeding. When already in a worktree session, choose an unused destination under that repository's `.claude/worktrees/` before creation, since `EnterWorktree` only accepts paths there. Honor an explicit user path; if it cannot be entered, report the limitation rather than substituting another location.

On leaving a worktree entered by this run, use `ExitWorktree` with `action: "keep"`, so the checkout remains resumable. If these tools are unavailable, use explicit absolute tool paths and working directories only if all required read/write access is already available. If entry is denied or access is missing, stop and report it; do not change permission settings or bypass a denial. See the [Claude Code tools reference](https://code.claude.com/docs/en/tools-reference) for availability and path restrictions.

Pass the worktree path to the independent reviewer. With `--watch`, perform every follow-up fix in this same checkout. Recheck its identity and status when resuming; do not infer that an existing directory is still at the expected branch.

Keep the worktree and branch when the run stops, including after PR creation or a monitoring timeout, so the user can resume. Report the PR URL, absolute worktree path and branch. Remove a worktree only when the user requests cleanup and its changes have been preserved; never remove it forcibly.
