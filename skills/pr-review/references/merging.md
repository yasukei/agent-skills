# Deciding whether the PR can be merged, and merging

Read this when deciding whether the PR can be merged (step 5 in SKILL.md), before posting an Approve, and before merging with `--merge`. Commands are in "Choosing the merge method" and "Merging" in `github-commands.md`.

## Merge conditions

The PR can be merged when all of these hold:

1. Every finding thread this skill opened is resolved (deferred ones too, after checking the issue).
2. No other reviewer's thread is unresolved and no Request changes remains. If one does, do not merge; ask the user.
3. All CI checks pass. Wait for pending checks to finish.
4. No conflicts, and branch protection rules (required approvals, etc.) are met. A required approval may be met by the Approve below.
5. The PR is not a draft.
6. **The PR description matches the implementation.** With a squash merge it becomes the commit message, so a description left stale by review changes leaves a wrong record. If it contradicts the implementation, post a new finding (usually P2; P1 if it misleads about behavior or compatibility) and wait for the update.
7. The head SHA at merge time is the last one you checked, so unchecked commits are never merged.

## Approve

When the PR author and the account running this skill differ, post an Approve review (a short record that the conditions are met, with the marker) once every condition except 4 is met, **whether or not `--merge` was given**: `issue-to-pr` takes the latest non-author Approve as its completion signal, and it may also satisfy a required approval in condition 4. On the same account, Approve is impossible; all threads resolved (or the no-findings review with the completion marker) is the signal instead.

## Without `--merge`

Report in chat that the PR can be merged and stop. Unsubscribe from PR events if subscribed.

## With `--merge`

Without `--watch`, merge only if every condition holds at this check; otherwise report which conditions are missing and end, without waiting for them.

1. Check which merge methods the repository allows.
2. Infer the method used for existing merged PRs from the base branch history and use the same one.
3. If it cannot be inferred, choose from the allowed methods in the order merge → squash → rebase.

Before merging, leave a short PR comment (with the marker) that all conditions are met, so the history can be followed later. Merge pinned to the checked head SHA, then delete the branch (or leave it to the repository's automatic deletion). Unsubscribe from PR events if subscribed. If the merge fails (branch protection, missing approvals, etc.), do not work around it; report to the user.
