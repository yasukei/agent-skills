# AGENTS.md

Agent skills shared by Claude Code, ChatGPT and Codex. Most work here is editing a skill in `skills/` or adding a new one.

## Language

- Write everything in this repository in English: skills, references, docs, scripts, tests, commits, PRs and issues. This applies even though the existing history is in Japanese.
- Exception: a skill's `description` may keep a few Japanese trigger phrases, because users ask in Japanese.
- Do not hard-code a natural language in skill instructions. What a skill writes (commits, PRs, issues, comments) follows the target repository's existing language, else the user's language. Chat replies use the user's language.

## Skill layout

- `skills/<name>/SKILL.md` with YAML frontmatter; `name` matches the directory.
- A skill references only files in its own directory (`references/`, `scripts/`, `assets/`), because skills are installed one directory at a time. Files in `scripts/` are executable.
- To add a skill, also add it to the skill table in `README.md`. The plugin manifests pick it up automatically.

## Writing skills

- SKILL.md: at most 200 lines and 7,000 bytes, because Codex inserts only the first 8,000 bytes of a skill. The whole file counts, frontmatter included, in UTF-8 bytes (`wc -c < SKILL.md`).
- Keep these in SKILL.md and preserve their meaning when shortening them:
  - The workflow and instructions needed on every run, because moving them saves no context and adds a file read every time.
  - Prohibitions, exit and stop conditions, and when the skill must ask the user. Preserve each of these rules' short reason clauses so agents can handle edge cases.
  - Markers, labels and completion signals shared by `issue-to-pr` and `pr-review` or by `orchestrate-issue` and `collect-observations`, because another skill relies on them.
  - A one-line pointer for each reference file that says when to read it, so the agent can load it when the workflow reaches that point.
- Move conditional workflow details first, such as handling an alternate target, resuming earlier work or using an optional mode. Put supporting commands, tables, examples and templates in `references/` or `assets/`.
- Move text word for word before editing it in the reference if needed, so the move can be checked for missing rules. Leave a one-line pointer in SKILL.md that says when to read the reference.
- `description`: what the skill does, when to use it, and when not to (name the neighboring skill). Keep it short.
- State the reason for each rule in a short clause; agents handle edge cases better when they know why.
- Skills that call `gh` must also work when GitHub GraphQL returns HTTP 403 (cloud sessions): give REST (`gh api repos/...`) alternatives in `references/`.
- `issue-to-pr` and `pr-review` interoperate through comment markers, priority labels and completion signals. Change both in the same PR.
- `collect-observations` reads the observations comments `orchestrate-issue` posts (their marker, groups and item IDs). Change both in the same PR.

## Before pushing

Commits use Conventional Commits with the skill name as scope (e.g. `feat(pr-review): ...`). Run the same checks as CI:

```bash
scripts/validate-skills.py
scripts/check-plugin-policy.py
tests/run.sh
claude plugin validate .
```
