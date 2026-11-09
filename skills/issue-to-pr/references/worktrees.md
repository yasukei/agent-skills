# Isolated implementation (`--worktree`)

Read before changing files or branches when `--worktree` is requested. It changes the checkout used for the work, not the skill's review, monitoring or merge permissions.

## Select the checkout

- Record the target `OWNER/REPO`, the original checkout's absolute path and the installed skill's absolute directory before changing directories. Run helpers from that skill directory, because a target repository need not contain them. Use explicit repository arguments for GitHub operations so a fork remote cannot redirect them.
- Choose the destination in this order: a path the user specified; a worktree location convention in the target repository's instructions; otherwise the running agent's default ("Destination" below). Check write permissions and request access if necessary. If creation fails, stop and report it rather than silently editing the original checkout.
- Inspect `git worktree list --porcelain`, local branches and the destination before creating anything. Reuse only a worktree for this repository and issue or PR: verify its Git common directory, branch and PR head repository. A matching directory name alone is not evidence.
- If the intended branch is held by the original checkout, report the conflict and ask how to proceed; do not switch that checkout or silently work there. This applies to both new issues and existing PRs.
- Check the candidate with `git -C "${worktree:?}" status --porcelain --untracked-files=all`. If dirty or in use by another session, preserve it and ask before using it; do not stash, reset, clean, overwrite or delete someone else's work. If an unrelated path exists, choose another unused path.
- Leave the original checkout's branch and files in place, including uncommitted changes. Worktrees share refs and objects, so fetches and the new branch are still visible in the repository. Do not use `--force` or `--ignore-other-worktrees`: Git's branch ownership protects concurrent work.

### Destination

Without a user path or repository convention, use the location where the running agent keeps its own worktrees. It does not depend on the checkout's parent directory being writable; in sandboxes that directory often is not. `<main>` is the main worktree's root, `<repo>` is its directory name, and `<id>` is `issue-<number>`, or `pr-<number>` for a PR without a linked issue.

| Agent | Destination |
|---|---|
| Claude Code | `<main>/.claude/worktrees/<id>` |
| Codex | `<root>/agent-skills/<repo>-<id>`, where `<root>` is Codex's worktree root: `${CODEX_HOME:-$HOME/.codex}/worktrees` unless changed in Codex's settings |
| Other | Ask the user for a path |

The `agent-skills/` subdirectory keeps these checkouts apart from the worktrees Codex itself manages, because Codex may delete older ones automatically.

Use the main worktree, not the current checkout: the current checkout may itself be a linked worktree, for example a `claude --worktree` session. For a non-bare repository the main worktree is the parent of the Git common directory. If that directory is not named `.git` (a bare repository or a separate Git directory), ask the user for a path.

```bash
common_dir=$(git -C "${original_checkout:?}" rev-parse --path-format=absolute --git-common-dir)
main_worktree=$(dirname "${common_dir:?}")
```

These rules apply to every destination, however it was chosen:

- Never place it inside another linked worktree. Removing a linked worktree also deletes anything nested in it, including uncommitted work, because Git treats ignored content as clean.
- A destination inside the main worktree must be ignored there. Otherwise the nested checkout shows as untracked, and `git add -A` in the main worktree would stage it as an embedded repository. Check before creating it, and stop and ask if the check fails:

  ```bash
  git -C "${main_worktree:?}" check-ignore -q "${worktree:?}"
  ```
- Tools run in the main or original checkout, such as linters and test globs, may pick up a nested worktree. Run checks only in the worktree ("Work and resume").

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

After Git creates the worktree or the checks above verify it for reuse or resumption, enter it with `EnterWorktree` when available, using its verified absolute `path`. Skip entry only if this session is already bound to that exact worktree; do not use `name`, which creates a different branch and checkout. This moves the session's working directory and write access, avoiding Bash's reset to the original project. Complete any permission prompt before proceeding. The Claude Code default destination is under `.claude/worktrees/`, because `EnterWorktree` accepts only paths there from subagents and existing worktree sessions. Honor an explicit user path or repository convention; if `EnterWorktree` cannot enter it, report the limitation rather than substituting another location.

On leaving a worktree entered by this run, use `ExitWorktree` with `action: "keep"`, so the checkout remains resumable. If these tools are unavailable, use explicit absolute tool paths and working directories only if all required read/write access is already available. If entry is denied or access is missing, stop and report it; do not change permission settings or bypass a denial. See the [Claude Code tools reference](https://code.claude.com/docs/en/tools-reference) for availability and path restrictions.

Pass the worktree path to the independent reviewer. With `--watch`, perform every follow-up fix in this same checkout. Recheck its identity and status when resuming; do not infer that an existing directory is still at the expected branch.

Keep the worktree and branch when the run stops, including after PR creation or a monitoring timeout, so the user can resume. Report the PR URL, absolute worktree path and branch. Remove a worktree only when the user requests cleanup and its changes have been preserved; never remove it forcibly.
