---
name: resolve-issue
description: Resolve GitHub issues by orchestrating an implementer (issue-to-pr) and a reviewer (pr-review) until each PR is ready to merge, or merged with --merge. Claude Code only; runs only when invoked explicitly. Not for implementing an issue yourself (use issue-to-pr) or reviewing a PR (use pr-review).
disable-model-invocation: true
---

# resolve-issue

Act as the orchestrator. Hand implementation and review to separate agents and drive the loop between them. **Do not implement, review or post to GitHub yourself.** That keeps each role's judgment separate. Also, a Claude Code subagent signs its comments with this session's ID, so your posts could be mistaken for the reviewer's.

## Environment

Claude Code only: the workflow needs subagents and background completion notifications. In any other agent (e.g. Codex), reply that `resolve-issue` is unsupported there and stop.

## Roles

| Role | Default agent | Start with | Skill invocation |
|---|---|---|---|
| Implementer | Codex | `codex exec` (`references/codex.md`) | `$<issue-to-pr> <issue> --worktree` |
| Reviewer | Claude Code | Agent tool subagent with `effort: "high"` | `<pr-review> <PR> --worktree` |

- `<issue-to-pr>` and `<pr-review>` are the names the skills are installed under: `agent-skills:<name>` from the plugin, plain `<name>` when installed as a standalone skill (`.claude/skills/<name>`, `.agents/skills/<name>`). For a Claude Code agent, use the name in your own skill list. For Codex, use `<name>` if the target checkout has `.agents/skills/<name>`, else `agent-skills:<name>`. A wrong name does not fail loudly: the agent would work without the skill's procedure.
- Replace a role's agent only when the user asks. A Claude Code implementer is a subagent; a Codex reviewer uses `codex exec` with `$<pr-review>`.
- Start Codex with `codex exec`, not through the Codex plugin's companion. The companion runs `--write` tasks in `workspace-write`, which overrides the user's Codex configuration (as of 2026-11-09).
- Do not set or change an agent's permissions, model or effort. Preparing them is the user's environment setup. The one exception is the reviewer's `effort: "high"` above.
- Keep each role's handle: the Codex `thread_id` and the reviewer subagent's ID. Resume the same agent for fixes and re-checks (`codex exec resume`, SendMessage), so it keeps its context.

## Arguments

- One or more issue numbers, optionally with `OWNER/REPO`.
- `--merge`: when a PR is ready, ask the reviewer to merge it with `--merge`. Without it, stop at ready to merge. If the user approves a merge later, send it to the same reviewer as `--merge`.
- `--delegate`: answer design questions that have a recommendation with that recommendation (type B in `references/decisions.md`).

## Rules

- Pass `--worktree` to both skills without a path, unless the user gave one. The skills choose a suitable location for each agent. Record the absolute paths the agents report.
- Do not use the Agent tool's `isolation: "worktree"`, because it would create a second worktree.
- Do not pass `--watch`; you drive the loop.
- Run every agent, and every wait for CI, in the background, and wait for its completion notification. Do not poll: each check spends a turn.
- Do not clean up the agents' temporary files or worktrees. They help with follow-up questions, and removing them is the user's call.
- Merge only through the reviewer with `--merge`, never yourself.
- Write handoffs in the user's language. The skills fall back to "the user's language" for commits, PRs and comments in a repository without history, and to them the handoff is the user. Report to the user in the user's language.
- For your own GitHub reads (issue dependencies, existing PRs, CI state), use `references/github-commands.md`. It also has REST fallbacks for when GraphQL returns HTTP 403.

## Workflow for one issue

Handoff texts are in `references/handoffs.md`.

1. **Implement.** Start the implementer. From its final report, record the PR URL, worktree, branch, checks run and CI state. Confirm the PR number with `gh`.
2. **Wait for CI.** Run `scripts/wait_ci.sh` in the background ("Waiting for CI" in `references/github-commands.md`). If it fails, resume the implementer with the failing checks, then wait again. If the implementer cannot fix it, or reports that the failure is unrelated to the PR, stop and ask the user.
3. **Review.** Start the reviewer on that PR. Record its verdict, findings, posts and worktree.
4. **Fix and re-check.** If there are findings, resume the implementer with the review URL and the finding links. Wait for CI as in step 2, then resume the reviewer to re-check.
5. **Round limit.** Count the reviewer's checks of a PR: the first review and each re-check. If the **3rd check** does not end in ready to merge, stop and ask the user, so two agents cannot loop forever. CI fixes made before a check (step 2) do not count. A CI failure the reviewer raises as a finding is part of that check.
6. **Finish.** When the reviewer reports ready to merge, ask it to merge if `--merge` was given; otherwise stop and report.

When an agent stops with a question, classify and handle it as `references/decisions.md` says. Relay an irregularity it reports to the user unless you can handle it as type C.

## Several issues

- Work serially, one issue at a time.
- If the issues' descriptions show dependencies (e.g. "Depends on", sub-issues), announce the order at the start.
- Without `--merge`, stop before an issue that depends on an unmerged one, and ask the user to merge first. Its branch must start from a default branch that contains the dependency.
- If one issue stops (a type A question, CI the implementer cannot fix, the round limit), stop the batch and report. Later issues may depend on it.

## Existing PR

If an issue already has an open PR, for example from an earlier session, continue from it instead of starting over:

- Start a new reviewer. It reads the PR's threads. It will ask before resolving threads opened by the earlier reviewer's session; that is a type A question for the user.
- For fixes, resume Codex with the `session` value from the `agent=codex` signature in the PR body, if `codex exec resume` accepts it. Otherwise start a new implementer run with "Implementer: existing PR" in `references/handoffs.md`.

## Final report

For each issue, report:

- PR URL and state: merged, ready to merge, or stopped and why.
- Decisions taken under `--delegate`, with the alternatives.
- Worktree paths the agents reported.
- Irregularities and how they were handled.
