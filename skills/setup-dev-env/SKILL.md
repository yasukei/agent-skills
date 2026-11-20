---
name: setup-dev-env
description: Set up the development environment of a freshly cloned repository (sbx sandbox, host PC or cloud), from runtime versions (.nvmrc, .python-version, ...) and devtools (npm, pnpm, yarn, uv, poetry, ...) through dependency install to a passing run of the existing tests, then summarize what was set up (e.g. 「開発環境をセットアップして」「cloneしたので環境構築して」「テストが通る状態にして」). Not for implementing changes (use issue-to-pr).
---

# setup-dev-env

Take a repository right after `git clone` to the point where its existing tests run, using the runtime versions and tools the repository asks for. The goal is the same environment CI and the maintainers use, so a test result here means what it means there.

## Rules

- **Do not commit, push or open PRs.** Setup is local; the user decides what, if anything, goes into the repository.
- **Do not rewrite tracked files.** Install from lockfiles as they are (frozen installs). If a lockfile is out of date or a tracked file changes during setup, revert that change and report it; regenerating a lockfile is a code change.
- **Do not fix code bugs to make tests pass.** Fix only the environment (see step 6). A test failing because of the code is a finding for the summary.
- **Installing:** through a tool already on the machine (nvm, fnm, mise, volta, asdf, pyenv, uv, corepack, pipx, npm -g into a managed Node, rustup, sdkman), go ahead. Ask first before installing a new version manager, running `curl | sh` installers, using `sudo`, or using system package managers (apt, dnf, brew, winget). Those change the machine beyond this project.
- **Secrets are the user's.** If setup needs a token or credential (private registry, `.env` values), stop on that item and ask; never invent values or work around authentication.
- **Shell completions never go into `/etc/sandbox-persistent.sh`.** It is sourced before every command; a completion script there breaks every later command.
- Chat and the summary use the user's language.

## Workflow

### 1. Survey

Run `scripts/detect.sh <repo>` (read-only). It reports the environment kind, every version pin with its source, lockfiles, manifests, setup hints and the tools on PATH.

Then read the setup hints it lists: README / CONTRIBUTING / AGENTS.md, the CI workflows, `.devcontainer`, `Makefile` / `justfile`, compose files. **The repository's own instructions and CI take precedence over this skill's defaults**; they are that repository's rules. Note from CI: runtime versions, install command, test command and any services or environment variables it sets.

If the repository has a setup script (`make setup`, `./scripts/bootstrap`, `./bin/setup`), read it before running it. Run it if it only does what this skill would do; if it uses sudo, system packages or changes global configuration, ask first.

### 2. Know the environment

Read `references/environments.md` for the detected kind (sbx sandbox, host PC, cloud). It covers how to make version-manager activation survive between commands, the sbx persistent file, network blocks (HTTP 403 with an explanation body) and direct vs. clone mode.

### 3. Runtimes

For each runtime the repository uses, decide the required version with `references/version-pins.md` (precedence among pin files, manifests, ranges and CI). Install it with the manager that is there, following `references/node.md`, `references/python.md` or `references/other-ecosystems.md`.

Then verify, in the same kind of shell the install and tests will run in, that the active version matches the requirement (commands in `references/version-pins.md`). Do not go on with a mismatched version: tests that pass on the wrong runtime prove nothing.

### 4. Devtools

Get the package manager the repository declares (`packageManager`, lockfile, README), at the declared version when one is given (e.g. corepack for pnpm/yarn, `pipx`/`uv tool` for poetry). Details per ecosystem are in the references above.

### 5. Dependencies

- Install with the frozen/locked command for that manager (`npm ci`, `pnpm install --frozen-lockfile`, `uv sync --locked`, ... in the references). Follow CI's extras/groups/workspace options.
- Monorepos: one install at the workspace root; separate projects with their own lockfile get their own install.
- Copy `.env.example` to `.env` only if the tests need it and `.env` is git-ignored, and only with non-secret defaults.
- Start services the tests need (database, etc.) the way the repository does (compose file, CI service definitions), when Docker is available.

### 6. Tests

Run the existing test suite with the command CI uses, else the standard one (`npm test`, `uv run pytest`, ...). Set `CI=true` so runners do not stay in watch mode. Long suites may run in the background.

When something fails, classify each failure before acting:

- **Environment** (missing dependency or system library, wrong runtime, missing browser, service not running, missing env var with a known default, network block): fix it within the Rules and rerun. Give up on one cause after three attempts and report it.
- **Needs the user** (secret, sudo, network approval, a paid/external service): stop on that item and ask, or report it as blocked.
- **Code** (assertion failures that are not environment-related, also failing in CI on the same commit, or flaky): do not fix. Report the test names and a one-line reason.

If CI's latest run on the same commit is available (`gh run list --commit <sha>`), use it to tell "broken here" from "broken everywhere".

### 7. Check and summarize

- `git status --porcelain` shows no changes to tracked files (only ignored or untracked setup output). Revert anything setup changed by accident, and mention it.
- Rerun the version check and one test command from a fresh shell (`bash -l -c '...'` in sbx) to confirm the setup survives a new shell.
- Write the summary with `assets/summary-template.md`: environment, runtimes (required / source / active / matches), tools and install commands, test results, changes outside and inside the repository, what is not done and needs the user, and the commands to rerun.

## Exit conditions

- **Done:** runtimes match, dependencies installed, and the tests run, with every failure classified. Report "Ready" (all pass) or "Ready with known failures" (only code failures remain).
- **Blocked:** a remaining failure needs the user (secret, approval, sudo, a decision on an unpinned version). Report what was finished and the exact action needed.
- Ask during the run only for those blockers and for the confirmations required by the Rules; decide everything else with the precedence rules and record the choice in the summary.
