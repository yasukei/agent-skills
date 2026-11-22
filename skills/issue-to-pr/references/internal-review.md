# Internal review request

Start the sub-agent with an independent context. Fill in the checkout path (absolute with `--worktree`), the base branch or SHA to diff against, and the issue as `OWNER/REPO#NUMBER`. Resolve the absolute path to this skill's `references/review-protocol.md` so the reviewer can read the shared priority definitions. Those values are all the context the request needs.

```text
Review the diff against <base branch or SHA> in <checkout path> for <OWNER/REPO#NUMBER>.

Keep the review read-only. Do not edit files, commit, push, post to GitHub, or change the checkout's state, including its branch, stash, and untracked files. You may read files and run commands that leave state unchanged.

Use the labels defined in "Findings and priority labels" in <absolute path to review-protocol.md>. For each finding, give the priority (P0 (Critical), P1 (High), P2 (Medium), P3 (Low), or Question), the location as file:line, what you found, why it matters, and what to do. If there are no findings, say "No findings."
```
