# Tests and checks

CI ([.github/workflows/ci.yml](../.github/workflows/ci.yml)) runs these on every PR and on pushes to `main`. Run the same commands locally from the repository root:

```bash
scripts/validate-skills.py      # validate SKILL.md
scripts/check-plugin-policy.py  # policy check of the four Claude / ChatGPT / Codex manifests
claude plugin validate .        # schema validation of the manifests in .claude-plugin/ (needs Claude Code)
tests/run.sh                    # lint and all tests
tests/run.sh lint               # bash -n and shellcheck only
tests/run.sh test               # tests only
```

## Required tools

`bash`, `git`, `jq`, `shellcheck`, `python3` with PyYAML, and Claude Code for `claude plugin validate .`. No network access or GitHub authentication is needed.

## `scripts/validate-skills.py`

Checks each skill directly under `skills/`. On problems, prints the file and field and exits with status 1.

- `SKILL.md` exists and starts with a YAML frontmatter.
- `name` matches the directory name and uses only lowercase letters, digits and hyphens, at most 64 characters (no leading, trailing or consecutive hyphens). `description` is non-empty and at most 1024 characters. These follow the [Agent Skills spec](https://agentskills.io/specification).
- The `references/`, `scripts/` and `assets/` paths and the relative Markdown link targets in the body exist in that skill's directory.
- Files under `scripts/` are executable.

## `scripts/check-plugin-policy.py`

Checks the two files in `.claude-plugin/`, the root `plugin.json` and `.agents/plugins/marketplace.json`. On violations, prints the reason and exits with status 1. This is not a full schema validation; it checks:

- The `name` in Claude's `marketplace.json` is not `agent-skills` (a reserved name that claude.ai's marketplace sync rejects).
- Neither `plugin.json` nor the catalogs' plugin entries have `version`. Claude distributes updates by commit SHA only when there is no `version`, and the ChatGPT / Codex manifests omit it too, for consistency.
- Both plugin definitions have a non-empty `name` and `description`, and they match. Each catalog's entry name matches its plugin definition.
- Each entry in the Codex catalog has a valid `policy.installation` and `policy.authentication` and a non-empty `category`.

## `claude plugin validate .`

Runs without authentication, so CI has no API key configured. The Claude Code version in CI is pinned (`CLAUDE_CODE_VERSION` in [ci.yml](../.github/workflows/ci.yml)) so that changed validation rules cannot suddenly break CI. It warns that there is no `version`; that follows the policy above, so `--strict` is not used.

## `tests/run.sh`

Runs [lint.sh](lint.sh) (`bash -n` and `shellcheck` on `scripts/*.sh`, `skills/*/scripts/*.sh` and the tests) and every `test_*.sh`. Each test file sources [lib.sh](lib.sh) for its assertions.

- **`test_setup.sh`** (`scripts/setup.sh`): creates, in a temporary directory, a local bare repository acting as the shared repository and a target repository, and runs `setup.sh` with `AGENT_SKILLS_URL` pointing to the former.
- **`test_pr_status.sh`** (`skills/issue-to-pr/scripts/pr_status.sh`): puts a fake `gh` ([fake-bin/gh](fake-bin/gh)) first in `PATH` to control its output and exit status. Each case runs on both the GraphQL path and the REST / CCR route path used where GraphQL returns 403, and checks that both give the same output.
- **`test_validate_skills.sh`** (`scripts/validate-skills.py`): breaks a skill created in a temporary directory one thing at a time and checks that validation fails and reports where.
- **`test_check_plugin_policy.sh`** (`scripts/check-plugin-policy.py`): does the same with manifests created in a temporary directory.

## CI jobs

The results of all jobs are combined in the `ci-ok` job. Branch protection only needs `ci-ok` as the required check; when adding a job, add it to `ci-ok`'s `needs`.
