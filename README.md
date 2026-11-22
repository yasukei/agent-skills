# agent-skills

Agent skills shared by Claude Code, ChatGPT and Codex.

## Skills

| Skill | Purpose |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | Write GitHub issues in a fixed format (task and bug templates) |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | Implement an issue, open a PR, and handle CI failures and review comments, also on a PR it did not open (`issue-to-pr #<PR>`); `--worktree` isolates the work, `--watch` monitors until ready to merge (never merges) |
| [pr-review](skills/pr-review/SKILL.md) | Review a PR with prioritized comments (P0–P3, Question), check responses and decide merge readiness; `--worktree` isolates local review, `--watch` monitors, `--merge` merges |
| [orchestrate-issue](skills/orchestrate-issue/SKILL.md) | Claude Code only, invoked explicitly. Orchestrate an implementer (Codex, `issue-to-pr`) and a reviewer (Claude Code subagent, `pr-review`) until each PR is ready to merge. Take agents' recommendations on eligible design questions by default, or use `--no-delegate` to ask the user. `--merge` merges through the reviewer, has each agent remove its worktree (`--keep-worktrees` keeps them), and runs `cleanup-local --pull`. |
| [cleanup-local](skills/cleanup-local/SKILL.md) | Prune remote-tracking refs, remove verified merged local branches and stale agent fetch refs, and optionally fast-forward the main checkout with `--pull` |
| [collect-observations](skills/collect-observations/SKILL.md) | Collect the observations comments `orchestrate-issue` posted on merged PRs (given by PR or issue numbers, sub-issues or a milestone) into one log issue with a status table, creating the log or appending to one and skipping PRs already collected |
| [setup-dev-env](skills/setup-dev-env/SKILL.md) | Set up a freshly cloned repository (sbx sandbox, host PC or cloud): pinned runtime versions, devtools, frozen dependency install and a run of the existing tests, ending with a summary of what was set up |

`orchestrate-issue` runs in the session's effort. To use a different one, set `/effort` before invoking. Skill frontmatter can change effort only for the current turn, and the orchestrator works across many turns.

Each skill lives in `skills/<name>/SKILL.md`.

## Installation

### As a Claude / Claude Code plugin

This repository is also a Claude plugin marketplace (`yasukei-agent-skills`).
The whole repository is one plugin, `agent-skills`, and the skills are available as `agent-skills:<skill name>` (e.g. `agent-skills:issue-to-pr`).

`.claude-plugin/plugin.json` has no `version`, so the version is the commit SHA and every commit to `main` is distributed as an update.

#### Claude Code

```text
/plugin marketplace add yasukei/agent-skills
/plugin install agent-skills@yasukei-agent-skills
```

#### claude.ai

A plugin registered on claude.ai is also synced to Claude Code (CLI and web) signed in with the same claude.ai account, and loaded as `agent-skills@synced`.
For what was verified on Claude Code on the web, see [Cloud environments](docs/cloud-environments.md#claude-code-on-the-web-and-plugins).

1. On claude.ai, open Customize → Plugins → Add marketplace
2. Enter the repository URL (`https://github.com/yasukei/agent-skills`)
3. Press Sync

After registering, delete any copies of the skills you imported into claude.ai by hand earlier (e.g. `create-issue`).
Otherwise two skills with the same description are listed, and the old one may be used.

### As a ChatGPT / Codex plugin

[plugin.json](plugin.json) at the root is the plugin definition in the Agent Plugins 1.0 format, and
[.agents/plugins/marketplace.json](.agents/plugins/marketplace.json) is the distribution catalog.
The whole repository is registered as one plugin, `agent-skills`, distributing the same skills in `skills/` as for Claude. `orchestrate-issue` reports itself unsupported outside Claude Code.
`version` is omitted (it is optional in the [official schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)).

#### Register the marketplace in Codex

```bash
codex plugin marketplace add yasukei/agent-skills
```

Then, in the ChatGPT desktop app's plugin list, choose `Yasukei Agent Skills` as the source and install `agent-skills`.
See the [official packaging and local installation guide](https://developers.openai.com/plugins/build/plugins) for details.

#### Update the Codex plugin

To update the installed plugin to the latest version, run:

```bash
codex plugin marketplace upgrade yasukei-agent-skills
```

#### Import into a ChatGPT workspace

A workspace admin opens Admin → Plugins → Add → Import marketplace and enters:

- Source: `https://github.com/yasukei/agent-skills`
- Path: empty (the repository root)
- Branch, tag, or commit: `main`

After importing, set the plugin's installation policy. Updates come with the daily sync, or with `Sync now`.
See the [official import and sync guide](https://help.openai.com/en/articles/20001504-importing-and-syncing-plugin-marketplaces-from-github) for details.

Running the skills needs an environment that can work on the target repository, commands such as `git` and `gh`, and GitHub authentication.

## Development

Rules for editing and adding skills are in [AGENTS.md](AGENTS.md). CI runs the same checks on every PR; run them locally before pushing:

```bash
uv lock --check                     # check that uv.lock matches pyproject.toml
uv run scripts/validate-skills.py   # validate SKILL.md (frontmatter, references, size) and shared files
scripts/check-plugin-policy.py      # check the four manifests against the repository's policy
uv run tests/run.sh                 # lint and all tests
claude plugin validate .            # validate the Claude manifests (needs Claude Code)
```

What each check covers, how the tests work and the tools they need are in [tests/README.md](tests/README.md).
Notes on cloud environments (Claude Code on the web, GitHub GraphQL being unavailable) are in [docs/cloud-environments.md](docs/cloud-environments.md).

## License

[MIT](LICENSE)
