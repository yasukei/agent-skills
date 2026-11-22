# Commands and GitHub REST lookups

Identify the canonical GitHub repository and verify the remote's **fetch** URL with `git remote -v`. Resolve an omitted target from the checkout's GitHub remote. Use the main entry from `git worktree list --porcelain -z` for the main checkout path. A bare main entry has no working directory to pull.

## Prune branch tracking refs

Snapshot `git for-each-ref --format='%(refname) %(objectname)' "refs/remotes/$remote/"` before fetching. Use the fetch's deletion entries to identify the pruned refs and the snapshot to report their SHAs.

Read `git config --get-all "remote.$remote.fetch"` and build the Bash array `branch_refspecs`. Keep positive mappings from `refs/heads/` into `refs/remotes/$remote/`, including aliases, and keep negative refspecs. Use the configured mappings so an existing upstream's tracking alias cannot be mistaken for a deleted branch. Limiting positive mappings to branch-tracking refs keeps tags and other local refs outside the operation. If no positive mapping fits, report that no supported branch-tracking mapping could be pruned and keep the local branches.

```bash
git fetch --prune --no-tags --no-prune-tags --no-write-fetch-head \
  --no-recurse-submodules --refmap= "$remote" "${branch_refspecs[@]}"
```

## Check and remove a worktree

Capture the invoking session's directory before changing directories. Parse `git worktree list --porcelain -z` as NUL-delimited fields and compare physical paths so a symlink or a session in a subdirectory cannot hide the current worktree. Keep the main entry and any worktree containing the session. Keep a candidate while another registered worktree is nested inside it, because Git can recursively delete an ignored nested worktree even if that nested worktree is locked or dirty.

For an attached checkout, use the upstream and merged PR checks under "Check a local branch" and verify the worktree HEAD matches the checked branch SHA. For a detached checkout, compare the full HEAD SHA with the `head_sha` values of merged PRs from the paginated target-repository lookup below. A closed but unmerged PR or an ancestor of a merged PR head does not qualify. Keep the worktree if a required check is inconclusive, including when the checkout is missing. Keep worktrees with a rebase or bisect in progress even if status is clean, because the operation may still hold unfinished work.

Read both `AGENTS.md` and `CLAUDE.md` and any worktree instructions they reference. Use trusted target-repository instructions that apply to the candidate. Check the matched PR's historical merge tree (`merge_commit_sha` below) as well as the default branch, because teardown may have changed since an older checkout was set up. Keep the checkout and report why if the applicable teardown cannot be established.

Under the guard described below, take a fresh worktree listing and check for locks, nested worktrees, the same branch or detached state and HEAD, and clean status from `git -C "$path" status --porcelain --untracked-files=all`. An empty result counts as clean only when the command succeeds. Before running teardown in a fork PR checkout, verify its checkout-local scripts and configuration against trusted target-repository content, because the fork head can differ from the merged tree. Keep the checkout and report why if those inputs cannot be verified. Run any documented teardown from the candidate worktree. If teardown fails, keep the checkout and report the command and result.

With the guard still held, repeat the worktree checks and, for an attached branch, verify it still qualifies. Then run `git worktree remove -- "$path"` from outside the candidate. Never add `--force`, unlock a candidate, or detach its branch to get past a refusal. If removal fails, report the error and what remains of the checkout and keep its branch. Before deleting a branch that a worktree held, confirm the removal succeeded and repeat the branch checks.

Files ignored by `.gitignore` are removed with the worktree, including any that exist only there and cannot be recreated (e.g. local settings or data an agent created or edited in the worktree). This data loss is accepted by design; do not check for or keep ignored files. After the merge, everything the repository needs has been committed, reviewed and merged, and ignored files are outside the repository by definition. An ignored file that should have been committed is an implementation or review miss, to be caught before the merge, not by keeping worktrees. Keeping every worktree with ignored files would also stop cleanup in any repository with installed dependencies.

### Coordinate with agent startup

Set `worktree` to the verified candidate path. Acquire the guard before the final worktree checks and hold it through teardown and removal. Release it when done with the candidate, including when skipping it or when teardown or removal fails. Keep and report a candidate if the guard cannot be acquired. Git can check its worktree lock just before another process acquires that lock, then remove the worktree anyway. The guard serializes cleanup and startup in these skills. Git commands run outside these skills can bypass the guard.

The startup and cleanup guard is the directory `<common-dir>/agent-skills-worktree-guards/<worktree-id>`. Use Git's absolute common directory and the linked worktree's absolute Git directory (`git -C "$worktree" rev-parse --path-format=absolute --git-common-dir` and `git -C "$worktree" rev-parse --absolute-git-dir`). Verify the common directory is the target repository's and that the Git directory is directly under its `worktrees/` directory. Use that Git directory's final component as the ID, because Git can give the worktree a different ID than its checkout basename.

Create the parent with `mkdir -p` and acquire the guard with plain `mkdir "$guard"`, which succeeds for only one caller. Release it with `rmdir "$guard"` only if this run acquired it. The guard lives outside the linked worktree's Git directory so removal cannot clear it while cleanup still holds it. Report failures and any guard left behind by a crash. Leave an existing guard in place, because another run may own it.

## Check a local branch

Use `LC_ALL=C git for-each-ref` over `refs/heads/` to get the full ref name, object ID, symbolic target, upstream remote, source ref and status (`%(refname)`, `%(objectname)`, `%(symref)`, `%(upstream:remotename)`, `%(upstream:remoteref)`, `%(upstream:track)`). For each direct branch with a gone upstream on the verified remote, confirm the source ref itself is gone with `git ls-remote --exit-code --refs "$remote" "$upstream_source"`. Only exit status 2 establishes absence. This distinguishes deletion from a missing tracking ref caused by fetch configuration.

Look up closed PRs by the target owner's head branch. A qualifying PR has a non-null `merged_at`, `.head.repo.full_name` equal to the target repository, `.head.ref` equal to the local branch name and `.head.sha` equal to the checked local SHA.

Immediately before deletion, check the invoking checkout's symbolic `HEAD` and the `branch` fields in `git worktree list --porcelain -z` for the full local branch ref. A rebase or bisect can detach HEAD while still using a branch. In each detached worktree, locate `rebase-merge/head-name`, `rebase-apply/head-name` and `BISECT_START` with `git -C "$path" rev-parse --path-format=absolute --git-path <file>`. Keep the branch if a rebase file names its full ref or `BISECT_START` names its short branch. If a worktree's use of the branch cannot be determined, keep it and report why.

## Check a private fetch ref

List direct refs and their IDs under `refs/agent-skills/`. Match exactly three nonempty path components beneath it, with a numeric middle component. The ref name carries no repository identity. In a checkout with remotes for different GitHub repositories, keep refs whose target repository cannot be established from run records, because the same number in another repository may still be open. Look up the number for an attributable ref in the target repository's issues endpoint, which covers issues, merged PRs and PRs closed without merging.

For each candidate, take a fresh `git worktree list --porcelain -z` snapshot after checking GitHub. For each valid worktree HEAD commit, list all full ref names containing it with `git for-each-ref --contains="$head" --format='%(refname)'`. If the candidate appears and is the only independent ref in that list, keep it. A symbolic ref pointing through the candidate does not count as independent. Attached and detached worktrees both count, including locked worktrees. Keep the candidate if a worktree HEAD can't be inspected, apart from a known bare checkout or an unborn branch with no commit.

## GitHub REST forms

Use these REST commands directly, including when GitHub's GraphQL API returns HTTP 403. Set `repo` to the verified canonical `OWNER/REPO`, `owner` to its owner, and `branch` to the local branch name without `refs/heads/`. Treat a failed lookup or missing required data as inconclusive.

```bash
gh api "repos/$repo" --jq '{full_name, default_branch}'
gh api --paginate --method GET "repos/$repo/pulls" \
  -f state=closed -f "head=$owner:$branch" -F per_page=100 \
  --jq '.[] | {number, merged_at, merge_commit_sha, head_ref: .head.ref, head_repo: .head.repo.full_name, head_sha: .head.sha}'
# Detached worktrees: collect merged heads across all pages, once for the pending candidates.
gh api --paginate --method GET "repos/$repo/pulls" \
  -f state=closed -F per_page=100 \
  --jq '.[] | select(.merged_at != null) | {number, merge_commit_sha, head_sha: .head.sha}'
gh api "repos/$repo/issues/$number" --jq .state
```

## Main checkout

Record the main checkout's branch and HEAD before cleanup. After pruning, obtain `default_sha` from the exact `refs/heads/$default` entry in `git ls-remote --exit-code --refs "$remote" "refs/heads/$default"`. If its commit is missing locally, fetch it by SHA with `git fetch --no-tags --no-prune-tags --no-write-fetch-head --no-recurse-submodules --refmap= "$remote" "$default_sha"`. Use `git rev-list --count "<main HEAD>..$default_sha"` before and after to count the commits the checkout is behind, independent of its upstream.

Only with `--pull`, check for ignored untracked paths using `git -C "$main" ls-files --others --ignored --exclude-standard -z` and compare them with the incoming paths from `git ls-tree -r --name-only -z "$default_sha"`. A pull can overwrite ignored files even with clean status. Treat equal paths and file/directory prefix collisions as blockers. Set `ignored_paths_clear=true` only if the check succeeds and finds no collisions. Pull the checked SHA so an upstream change cannot invalidate this check. Disable autostash so the pull cannot hide work that appears after the status check.

```bash
if [ "$ignored_paths_clear" = true ] &&
  status=$(git -C "$main" status --porcelain --untracked-files=all) &&
  [ -z "$status" ] &&
  [ "$(git -C "$main" symbolic-ref --quiet HEAD)" = "refs/heads/$default" ]; then
  git -C "$main" pull --ff-only --no-rebase --no-squash --no-autostash \
    --no-tags --no-prune --no-recurse-submodules --refmap= "$remote" "$default_sha"
fi
```
