# agent-skills

Agent skills shared by Claude Code, ChatGPT and Codex.

## Skills

| Skill | Purpose |
|---|---|
| [create-issue](skills/create-issue/SKILL.md) | Write GitHub issues in a fixed format (task and bug templates) |
| [issue-to-pr](skills/issue-to-pr/SKILL.md) | Implement an issue, open a PR, and handle CI failures and review comments; monitors the PR until it is ready to merge only with `--watch` (never merges) |
| [pr-review](skills/pr-review/SKILL.md) | Review a PR with prioritized comments (P0–P3, Question), check the responses and decide whether it can be merged (monitors the PR only with `--watch`, merges only with `--merge`) |

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
The whole repository is registered as one plugin, `agent-skills`, distributing the same three skills in `skills/` as for Claude.
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
Where the plugin is installed, putting the same skills in `.agents/skills/` too duplicates them, so use only one of the two installation methods.

### As a git submodule

Not needed if both Claude and Codex get the skills from the plugin.
The repository is added as a submodule, and `.claude/skills/` and `.agents/skills/` get one symbolic link per skill.
Linking per skill lets the repository's own skills live in the same directories.

Run [scripts/setup.sh](scripts/setup.sh) inside the target repository:

```bash
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash
git commit -m "chore: add shared agent skills"
```

What the script does:

- Adds the repository at `.agent-skills` as a submodule tracking the `main` branch (skipped if already added)
- Creates symbolic links to each skill at `.claude/skills/<name>` and `.agents/skills/<name>` (an option limits this to one side)
- If the repository has its own skill with the same name (a real directory, or a link to somewhere other than `.agent-skills`), warns and skips it instead of overwriting
- Removes links to skills that were removed from the shared repository
- Stages the changes (never commits)

It is safe to run any number of times, so rerun it after skills are added to or removed from this repository to bring the links up to date.

#### Using the submodule for one side only

When one side uses the plugin and the other the submodule, use these options:

| Option | Where links are created | Where links this script created earlier are removed |
|---|---|---|
| None | `.claude/skills/` and `.agents/skills/` | Nowhere |
| `--codex-only` | `.agents/skills/` | `.claude/skills/` |
| `--claude-only` | `.claude/skills/` | `.agents/skills/` |

Claude from the plugin, links for Codex only:

```bash
# First time
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash -s -- --codex-only
# To switch a repository that already has it
.agent-skills/scripts/setup.sh --codex-only

git commit -m "chore: link shared agent skills for Codex only"
```

Codex from the plugin, links for Claude only:

```bash
# First time
curl -fsSL https://raw.githubusercontent.com/yasukei/agent-skills/main/scripts/setup.sh | bash -s -- --claude-only
# To switch a repository that already has it
.agent-skills/scripts/setup.sh --claude-only

git commit -m "chore: link shared agent skills for Claude only"
```

Both remove only the links this script created pointing into the submodule's `skills/`. The repository's own real directories and links to other places are left alone.
`--codex-only` and `--claude-only` cannot be used together. Either can be combined with `--update`.

Installing both the plugin and links to the same skills lists two skills with the same description.
If the submodule is outdated, which of the old and new versions is used can differ from conversation to conversation, so use only one.

`--codex-only` / `--claude-only` are not remembered. Running without them recreates the links on both sides, so pass the option every time, including with `--update`.

#### Update policy

The submodule always follows the latest `main`. `--update` updates the submodule to the latest, then recreates the links.

```bash
.agent-skills/scripts/setup.sh --update
# In a repository set up with --codex-only
.agent-skills/scripts/setup.sh --update --codex-only
# In a repository set up with --claude-only
.agent-skills/scripts/setup.sh --update --claude-only

git commit -m "chore: update shared agent skills"
```

In cloud environments (Codex Cloud, Claude Code on the web), the submodule may need to be initialized in the environment's setup script; see [Cloud environments](docs/cloud-environments.md#submodule-initialization).

## Development

Rules for editing and adding skills are in [AGENTS.md](AGENTS.md). CI runs the same checks on every PR; run them locally before pushing:

```bash
scripts/validate-skills.py      # validate SKILL.md (frontmatter, references, size) and shared files
scripts/check-plugin-policy.py  # check the four manifests against the repository's policy
tests/run.sh                    # lint and all tests
claude plugin validate .        # validate the Claude manifests (needs Claude Code)
```

What each check covers, how the tests work and the tools they need are in [tests/README.md](tests/README.md).
Notes on cloud environments (Claude Code on the web, GitHub GraphQL being unavailable, submodule initialization) are in [docs/cloud-environments.md](docs/cloud-environments.md).
