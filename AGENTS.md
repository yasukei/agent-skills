# AGENTS.md

Agent skills shared by Claude Code, ChatGPT and Codex. Most work here is editing a skill in `skills/` or adding a new one.

## Language

- Write everything in this repository in English: skills, references, docs, scripts, tests, commits, PRs and issues. This applies even though the existing history is in Japanese.
- Exception: a skill's `description` may keep a few Japanese trigger phrases, because users ask in Japanese.
- Do not hard-code a natural language in skill instructions. What a skill writes (commits, PRs, issues, comments) follows the target repository's existing language, else the user's language. Chat replies use the user's language.

## Skill layout

- `skills/<name>/SKILL.md` with YAML frontmatter; `name` matches the directory.
- A skill references only files in its own directory (`references/`, `scripts/`, `assets/`), because skills are installed one directory at a time. Files in `scripts/` are executable.
- To add a skill, also add it to the skill table in `README.md`. The plugin manifests and `scripts/setup.sh` pick it up automatically.

## Writing skills

- SKILL.md: at most 200 lines and 7,000 bytes, because Codex inserts only the first 8,000 bytes of a skill. The whole file counts, frontmatter included, in UTF-8 bytes (`wc -c < SKILL.md`). Keep the workflow, prohibitions and exit conditions there; move commands, tables, examples and templates to `references/` or `assets/`, and say when to read each file.
- `description`: what the skill does, when to use it, and when not to (name the neighboring skill). Keep it short.
- State the reason for each rule in a short clause; agents handle edge cases better when they know why.
- Skills that call `gh` must also work when GitHub GraphQL returns HTTP 403 (cloud sessions): give REST (`gh api repos/...`) alternatives in `references/`.
- `issue-to-pr` and `pr-review` interoperate through comment markers, priority labels and completion signals. Change both in the same PR.

## Before pushing

Commits use Conventional Commits with the skill name as scope (e.g. `feat(pr-review): ...`). Run the same checks as CI:

```bash
scripts/validate-skills.py
scripts/check-plugin-policy.py
tests/run.sh
claude plugin validate .
```
