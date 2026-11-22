# Conflicts with the base branch

Read when a conflict is detected, before handing off review fixes or a merge, or when the reviewer reports that a conflict or changed merge state blocked approval or merging.

## Checking

- Before the first review and each re-check, use the mergeability result from the CI wait (step 2). Use the result for the head SHA in that output.
- Before a merge handoff, before dispatching review fixes, and when the reviewer reports that a conflict or a changed merge state blocked approval or merging, run `wait_ci.sh --mergeability-only` with the PR and repository in the background ("Checking for a conflict" in `github-commands.md`). A fresh check matters because the base branch can advance during review. If the same reviewer report calls for both a conflict check and a review-fix handoff, use one check for both.
- If a conflict blocked the reviewer but has since cleared, wait for CI and have the reviewer re-check before sending a merge handoff. Send any outstanding findings to the implementer first.

## Resolving

1. Resume the implementer with "Implementer: conflict" in `handoffs.md`. If reviewer findings also need fixes, send the finding links and the conflict in a single handoff. If CI failures were listed for the same head, include those links too.
2. Record the resolution commit and conflicting files. If the implementer cannot resolve the conflict or asks about a large conflict, stop and ask the user. The reviewer and orchestrator leave the resolution to the implementer.
3. After the push, return to step 2 and wait for CI on the new head. Once CI permits review and the PR has no conflict, start the first review if the reviewer has yet to start. Otherwise resume the same reviewer with "Reviewer: re-check" in `handoffs.md`, identifying the conflict resolution commit. The reviewer checks the new head even if it approved the previous one.
4. If a conflict interrupted a merge, send the merge handoff again only after the re-check is ready and the fresh pre-merge check passes.

Apply the round-limit rule in SKILL.md. For a conflict-resolution merge, the base branch commits brought in by the merge do not count as new PR-branch commits.
