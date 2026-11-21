# Environment-specific notes

`scripts/detect.sh` reports the kind of environment under "## environment".

## Making activation stick between commands

Every Bash call of an agent runs a new non-interactive shell. `~/.bashrc` is usually not read, and a shell function (nvm, sdkman) or `eval "$(... activate)"` from one call is gone in the next. Choose one:

- Prefix each command with the activation (`. "$NVM_DIR/nvm.sh" && nvm use && npm test`). Always works; use it while experimenting.
- Prefer managers whose shims are files on PATH (mise shims, volta, pyenv shims, asdf), or tool-run commands (`uv run`, `poetry run`, `mise exec --`), which need no activation.
- Persist it for later sessions, as below. Then verify from a fresh shell (`bash -l -c 'node --version'`).

## sbx sandbox

- `/etc/sandbox-persistent.sh` is sourced before every command (through `BASH_ENV`) and by login shells. Append activation there so later commands and sessions see it:

  ```bash
  echo 'export NVM_DIR="$HOME/.nvm"' >> /etc/sandbox-persistent.sh
  echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /etc/sandbox-persistent.sh
  ```

- **Never add shell completion scripts** (`bash_completion`, `etc/bash_completion.sh`) to that file. It runs before every command, outside a completion context, and breaks the shell so that every command prints nothing. If that happens, remove the line and ask the user to restart the session.
- Do not append a line that is already there; check with `grep -F` first, because the file grows with every rerun otherwise.
- If a tool is not found right after it was installed, retry with `bash -l -c '<command>'`; the command shell may hold a stale environment.
- Some sbx images set `NPM_CONFIG_PREFIX` in the container environment (for example, `/usr/local/share/npm-global`). With it set, nvm reports `nvm is not compatible with the "NPM_CONFIG_PREFIX" environment variable`. Check the prefix directory for globally installed tools that would become unreachable. If none depend on it, add `unset NPM_CONFIG_PREFIX` to `/etc/sandbox-persistent.sh` **before** the line that sources `nvm.sh`.
- Docker Hardened Images (DHI) based on Debian 13 can lack `libatomic1`. Official Node binaries (observed with Node 26.13.1 installed via nvm) can fail with `node: error while loading shared libraries: libatomic.so.1: cannot open shared object file`. Ask for confirmation before running `sudo apt-get update && sudo apt-get install -y libatomic1`, since it uses `sudo` and installs a system package.
- When planning a Node install on an affected image, ask in one question for approval to install any needed version manager and `libatomic1`. Include Playwright `--with-deps` in the same question if the project needs it.
- Network: blocked requests return HTTP 403 with an explanation in the body. Read it and relay the exact next step to the user (approve the pending request, or `sbx policy allow network <domain>` on the host); do not switch to other mirrors to get around it. Domains setup typically needs: `registry.npmjs.org`, `nodejs.org`, `pypi.org`, `files.pythonhosted.org`, `github.com` and `objects.githubusercontent.com` (uv Python builds, many installers), `repo.maven.apache.org`, `services.gradle.org`, `proxy.golang.org`, `static.crates.io`, `index.crates.io`, `rubygems.org`.
- Docker is available; services the tests need (databases, queues) can be started with the repository's compose file. A port published from a container is reachable as `localhost`.
- Git mode: in direct mode the working tree is the host's, so `node_modules`, `.venv` and build output also appear on the host. Native binaries built here are for the sandbox's OS and CPU (`uname -sm`) and may not run on the host (e.g. a macOS host); say so in the summary. In clone mode nothing reaches the host until it fetches.

## Host PC

- Do not edit shell startup files (`~/.bashrc`, `~/.zshrc`, PowerShell profile) or global configuration (`npm config set -g`, `git config --global`) without asking; they affect everything else the user runs. Use per-command activation instead and tell the user what to add if they want it permanent.
- No `sudo` and no system package managers (`apt`, `dnf`, `brew`, `winget`, `choco`) without asking.
- Windows: commands differ (`.venv\Scripts\python`, `$env:CI = "true"`). Use the shell the agent actually has, and say which one in the summary.

## Cloud sessions (Claude Code on the web, Codex)

- The machine is temporary: what you install is lost when the session ends. Offer the commands you used as the environment's setup script, so the next session starts ready.
- Network may be limited or off. When an install fails on the network, report which host was unreachable instead of retrying.
- In a Codex sandbox, commands that need the network or write outside the workspace need the user's approval through Codex's own approval prompt.
