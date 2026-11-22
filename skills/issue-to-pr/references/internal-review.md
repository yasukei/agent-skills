# Internal review request

Use the full SHA recorded when the implementation branch was created. For a branch created with `--worktree`, this is the `base_sha` used to create it in `references/worktrees.md`. If that SHA is unavailable when reusing a branch or resuming work, fetch the target repository's default branch to refresh its remote-tracking ref, then use the SHA returned by `git merge-base HEAD <remote>/<default-branch>`. A branch name can resolve to a stale commit and bring unrelated changes into the review.

Start the sub-agent with an independent context. Fill in the checkout path (absolute with `--worktree`), the review base SHA, and the issue as `OWNER/REPO#NUMBER`. Resolve the absolute path to this skill's `references/review-protocol.md` so the reviewer can read the shared priority definitions. Those values are all the context the request needs.

```text
Review the changes for <OWNER/REPO#NUMBER> from <review base SHA> to the current working tree at <checkout path>. Run `git diff <review base SHA> --` there to see committed, staged, and unstaged changes to tracked files. Use `git ls-files --others --exclude-standard` to find untracked files and read any that are part of the implementation.

Keep the review read-only. Do not edit files, commit, push, post to GitHub, or change the checkout's state, including its branch, stash, and untracked files. You may read files and run commands that leave state unchanged.

Use the labels defined in "Findings and priority labels" in <absolute path to review-protocol.md>. For each finding, give the priority (P0 (Critical), P1 (High), P2 (Medium), P3 (Low), or Question), the location as file:line, what you found, why it matters, and what to do. If there are no findings, say "No findings."
```
