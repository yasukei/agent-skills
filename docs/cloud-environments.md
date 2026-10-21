# Cloud environments

Notes on using these skills in cloud environments (Claude Code on the web, Codex Cloud). Verified findings carry their date, because the environments change.

## Claude Code on the web and plugins

Whether Claude Code on the web loads the plugin synced from claude.ai (`agent-skills@synced`) decides how to use `setup.sh`:

- If it is loaded: Claude can rely on the plugin alone. If Codex also uses the plugin, no submodule is needed. If Codex uses the submodule, pass `--codex-only`.
- If it is not loaded: links for Claude are needed. If Codex uses the plugin, pass `--claude-only`; if both use the submodule, pass neither option.

Result: **it is loaded** (verified on 2026-10-17). Claude can rely on the plugin alone on the web too.

- The plugin registered on claude.ai is synced to `~/.claude/plugins/synced/<organization ID>_<ID>/agent-skills/`.
- The three skills are available as `agent-skills:create-issue`, `agent-skills:issue-to-pr` and `agent-skills:pr-review`.
- The synced `skills/` matched the latest `main`.
- The sync target of skills imported into claude.ai by hand (`~/.claude/skills/synced/`) had no skills with the same names, so nothing was duplicated.

## GitHub GraphQL is not available

In Claude Code on the web sessions, the GitHub GraphQL API is rejected with `HTTP 403: GitHub GraphQL is not available from Claude Code sessions` (verified on 2026-10-20). Besides `gh api graphql`, `gh` commands that use GraphQL internally fail too, such as `gh pr view`, `gh pr checks`, `gh pr list`, `gh issue view` and `gh repo view`. REST (`gh api repos/...`) and the CCR route for review threads (`gh api repos/{owner}/{repo}/pulls/{n}/ccr/review_threads`, etc.) work.

- `skills/issue-to-pr/scripts/pr_status.sh` switches to REST and the CCR route automatically when GraphQL returns 403.
- Each skill documents the replacement commands: [create-issue](../skills/create-issue/SKILL.md), [issue-to-pr](../skills/issue-to-pr/references/github-commands.md), [pr-review](../skills/pr-review/references/github-commands.md).

## Submodule initialization

Codex Cloud and Claude Code on the web may not initialize submodules automatically, so put this in the environment's setup script. `--remote` fetches the latest `main` instead of the recorded commit.

```bash
git submodule update --init --recursive --remote
```

When the fetched commit is newer than the recorded one, `git status` shows `.agent-skills` as modified. To keep it out of unrelated commits, update the submodule in a separate commit as described in [Update policy](../README.md#update-policy).
