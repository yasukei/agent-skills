# Cloud environments

Notes on using these skills in cloud environments (Claude Code on the web, Codex Cloud). Verified findings carry their date, because the environments change.

## Claude Code on the web and plugins

Whether Claude Code on the web loads the plugin synced from claude.ai (`agent-skills@synced`) decides whether the plugin is enough there.

Result: **it is loaded** (verified on 2026-10-17). Claude can rely on the plugin alone on the web too.

- The plugin registered on claude.ai is synced to `~/.claude/plugins/synced/<organization ID>_<ID>/agent-skills/`.
- The three skills are available as `agent-skills:create-issue`, `agent-skills:issue-to-pr` and `agent-skills:pr-review`.
- The synced `skills/` matched the latest `main`.
- The sync target of skills imported into claude.ai by hand (`~/.claude/skills/synced/`) had no skills with the same names, so nothing was duplicated.

## GitHub GraphQL is not available

In Claude Code on the web sessions, the GitHub GraphQL API is rejected with `HTTP 403: GitHub GraphQL is not available from Claude Code sessions` (verified on 2026-10-20). Besides `gh api graphql`, `gh` commands that use GraphQL internally fail too, such as `gh pr view`, `gh pr checks`, `gh pr list`, `gh issue view` and `gh repo view`. REST (`gh api repos/...`) and the CCR route for review threads (`gh api repos/{owner}/{repo}/pulls/{n}/ccr/review_threads`, etc.) work.

- `skills/issue-to-pr/scripts/pr_status.sh` switches to REST and the CCR route automatically when GraphQL returns 403.
- Each skill documents the replacement commands: [create-issue](../skills/create-issue/SKILL.md), [issue-to-pr](../skills/issue-to-pr/references/github-commands.md), [pr-review](../skills/pr-review/references/github-commands.md).
