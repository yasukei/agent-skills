---
name: orchestrate-issue
description: Resolve GitHub issues by orchestrating an implementer (issue-to-pr) and a reviewer (pr-review) until each PR is ready to merge, or merged with --merge. Claude Code only; runs only when invoked explicitly. Not for implementing an issue yourself (use issue-to-pr) or reviewing a PR (use pr-review).
disable-model-invocation: true
---

# orchestrate-issue

Act as the orchestrator. Hand implementation and review to separate agents and drive the loop between them. **Do not implement, review or post to GitHub yourself**, except the observations comment after a merge. That keeps each role's judgment separate. Also, a Claude Code subagent signs its comments with this session's ID, so your posts could be mistaken for the reviewer's.

## Environment

Claude Code only: the workflow needs subagents and background completion notifications. In any other agent (e.g. Codex), reply that `orchestrate-issue` is unsupported there and stop.

## Roles

| Role | Default agent | Start with | Skill invocation |
|---|---|---|---|
| Implementer | Codex | `codex exec` (`references/codex.md`) | `$<issue-to-pr> <issue> --worktree` |
| Reviewer | Claude Code | Agent tool subagent with `effort: "high"` | `<pr-review> <PR> --worktree` |

- Before starting an agent, read "Installed skill names" in `references/handoffs.md`. A wrong name does not fail loudly: the agent would work without the skill's procedure.
- Replace a role's agent only when the user asks. A Claude Code implementer is a subagent; a Codex reviewer uses `codex exec` with `$<pr-review>`.
- Start Codex with `codex exec`, not through the Codex plugin's companion. The companion runs `--write` tasks in `workspace-write`, which overrides the user's Codex configuration (as of 2026-11-09).
- Do not set or change an agent's permissions, model or effort. Preparing them is the user's environment setup. The one exception is the reviewer's `effort: "high"` above.
- Keep each role's handle: the Codex `thread_id` and the reviewer subagent's ID. Resume the same agent for fixes and re-checks (`codex exec resume`, SendMessage), so it keeps its context.

## Arguments

- One or more issue numbers, optionally with `OWNER/REPO`.
- `--merge`: when a PR is ready, ask the reviewer to merge it with `--merge`. Without it, stop at ready to merge. If the user approves a merge later, send it to the same reviewer as `--merge`.
- `--no-delegate`: ask the user about type B design questions. By default, take the agent's recommendation (`references/decisions.md`).
- `--keep-worktrees`: keep the agents' worktrees after a merge.

## Rules

- Pass `--worktree` to both skills without a path, unless the user gave one. The skills choose a suitable location for each agent. Record the absolute paths the agents report.
- Do not use the Agent tool's `isolation: "worktree"`, because it would create a second worktree.
- Do not pass `--watch`; you drive the loop.
- Run every agent, and every wait for CI, in the background, and wait for its completion notification. Do not poll: each check spends a turn.
- Do not remove the agents' files or worktrees yourself. After a merge, each agent removes its own (`references/cleanup.md`).
- Merge only through the reviewer with `--merge`, never yourself.
- Write handoffs, follow-ups and answers to agents in English, as "Language" in `references/handoffs.md` says. Talk to the user in the user's language.
- For your own GitHub calls, use `references/github-commands.md`. It has REST fallbacks for when GraphQL returns HTTP 403.

## Workflow for one issue

Read `references/handoffs.md` before writing handoffs. If the issue already has an open PR, follow that file's instructions for continuing it.

1. **Implement.** Start the implementer. From its final report, record the PR URL, worktree, branch, checks run and CI state. Confirm the PR number with `gh`.
2. **Wait for CI and check for conflicts.** Run `scripts/wait_ci.sh` in the background before the first review and each re-check ("Waiting for CI" in `references/github-commands.md`). If CI fails, resume the implementer with the failing checks, then wait again. If the implementer cannot fix it, or reports that the failure is unrelated to the PR, stop and ask the user.
3. **Review.** Start the reviewer on that PR. Record its verdict, findings, posts and worktree.
4. **Fix and re-check.** If there are findings, resume the implementer with the review URL and the finding links. Wait for CI as in step 2, then resume the reviewer to re-check.
5. **Round limit.** Count the first review and each re-check after a fix of review findings (step 4), including when the fix and a conflict resolution come from the same handoff. A re-check after only conflict resolutions and CI fixes (step 2) does not count. After the **3rd counted check**, follow the conflict procedure and run an uncounted re-check if a conflict is the sole blocker. Stop and ask the user if the latest result falls short of ready to merge, so two agents cannot loop forever. A CI failure the reviewer raises as a finding is part of that check.
6. **Finish.** When the reviewer reports ready to merge, check for conflicts before sending the merge handoff if `--merge` was given. Without it, stop and report. After a merge, post the observations on the PR (`references/observations.md`) and clean up (`references/cleanup.md`).

Read `references/conflicts.md` when a check detects a conflict, before handing off review fixes or a merge, or when a conflict or changed merge state blocks the reviewer. Send the conflict to the implementer, wait for CI, and have the reviewer check the new head. If the implementer cannot resolve the conflict or asks about a large one, stop and ask the user.

Collect the observations each agent reports that are not findings. Do not pass them to the implementer: acting on them would widen the PR. When an agent stops with a question, classify and handle it as `references/decisions.md` says. Relay an irregularity it reports to the user unless you can handle it as type C.

## Several issues

- Work serially, one issue at a time.
- If the issues' descriptions show dependencies (e.g. "Depends on", sub-issues), announce the order at the start.
- Without `--merge`, stop before an issue that depends on an unmerged one, and ask the user to merge first. Its branch must start from a default branch that contains the dependency.
- On a type A question, unfixable CI, or the round limit, stop the batch because later issues may depend on it. Clean up (`references/cleanup.md`) before reporting.

## Final report

For each issue, report:

- PR URL and state: merged, ready to merge, or stopped and why.
- Recommendations taken by default, with the alternatives.
- Observations: the comment's URL, or the items and why they were not posted (`references/observations.md`).
- Worktrees kept (path and reason) or removed. Local cleanup (deleted refs, why others stayed, main checkout).
- Irregularities and how they were handled.
