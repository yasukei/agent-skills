# Node.js projects

## Installing the Node version

Use the version manager that is already on the machine (`scripts/detect.sh`, "## tools"). Each Bash call of an agent is a new non-interactive shell, so a manager that works by modifying the current shell must be activated in every command, or persistently (see `references/environments.md`).

| Manager | Install the pinned version | Activate in a fresh shell |
|---|---|---|
| mise | `mise install` (reads `mise.toml`, `.tool-versions`, `.nvmrc` with idiomatic files enabled) | `mise exec -- <cmd>` or `eval "$(mise activate bash)"`; for non-interactive shells prefer `export PATH="$HOME/.local/share/mise/shims:$PATH"` |
| nvm | `. "$NVM_DIR/nvm.sh" && nvm install` (reads `.nvmrc`; or `nvm install <version>`) | `. "$NVM_DIR/nvm.sh" && nvm use`; `nvm alias default <version>` makes new shells pick it |
| fnm | `fnm install` (reads `.nvmrc` / `.node-version`) | `eval "$(fnm env --use-on-cd)" && fnm use` |
| volta | `volta install node@<version>` (volta also follows `package.json` `volta.node` automatically) | nothing; volta's shims are on PATH |
| asdf | `asdf install nodejs <version>` (needs the nodejs plugin) | asdf's shims on PATH |

No manager present: installing one (nvm, fnm, mise, volta) changes the machine, so ask the user first, and suggest the one the repository mentions. Do not use `apt install nodejs` or similar; distribution packages rarely match the pin.

## The package manager

Decide from, in order: `package.json` `packageManager` (e.g. `pnpm@9.1.0`), then the lockfile (`scripts/detect.sh`, "## package managers"), then the README. Several lockfiles at the root is a repository problem; use the one CI uses and report it.

Getting the pinned pnpm / yarn:

- `packageManager` set: `corepack enable` and the shims fetch that exact version. If it fails because Node's bin directory is not writable (system Node), use `corepack enable --install-directory "$HOME/.local/bin"` and make sure that directory is on PATH. Node 25 and later no longer bundle corepack; install it with `npm install -g corepack` first.
- No `packageManager`: `npm install -g pnpm@<major>` or `npm install -g yarn` (into the version manager's Node, so no sudo), choosing the major that matches the lockfile version (`pnpm-lock.yaml` `lockfileVersion: '9.0'` → pnpm 9 or 10).
- bun: `npm install -g bun`, or the user's choice of installer (ask before `curl | bash`).

## Installing dependencies

Use the lockfile as it is, so the result matches CI and the lockfile is not rewritten:

| Manager | Command |
|---|---|
| npm | `npm ci` |
| pnpm | `pnpm install --frozen-lockfile` |
| yarn berry (`__metadata` in yarn.lock) | `yarn install --immutable` |
| yarn classic | `yarn install --frozen-lockfile` |
| bun | `bun install --frozen-lockfile` |

- Workspaces/monorepos: run the install once at the root; it covers all workspace packages. Separate projects with their own lockfile in subdirectories need their own install.
- If the frozen install fails because the lockfile is out of date, do not regenerate it. Report it; an unfrozen install changes a tracked file.
- `postinstall` scripts that build native modules (node-gyp) may need `python3`, `make` and a C compiler. A missing compiler is an environment problem; ask before installing it with the system package manager.
- Private registries (`.npmrc` with `${NPM_TOKEN}`): the token is a secret the user must provide. Report it as a blocker instead of working around it.

## Running the tests

- Use the command CI runs, else `scripts.test` (`npm test`, `pnpm test`, `yarn test`, `bun run test`).
- Set `CI=true` for the run. Without a TTY, some runners still start in watch mode (vitest outside CI, `jest --watch` scripts, `react-scripts test`) and never exit.
- Browser tests (Playwright, Cypress) need browsers: `npx playwright install <browser>` downloads them. `--with-deps` installs system packages with sudo, so ask first.
- A test script that needs a build first (`pretest`, or CI runs `build` before `test`) follows CI's order.
