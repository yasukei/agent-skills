# Deciding the required runtime version

`scripts/detect.sh` prints every pin it finds, one line per source. Use this file to decide which version to install and to check that it is the one in use.

## Precedence

When sources disagree, use the first that applies, and report the disagreement in the summary (it is usually a bug in the repository, not something to fix during setup):

1. The repository's own setup instructions (README, CONTRIBUTING, AGENTS.md, devcontainer), when they name a version.
2. An exact pin file read by version managers: `.nvmrc`, `.node-version`, `.python-version`, `.tool-versions`, `mise.toml` `[tools]`, `.ruby-version`, `.java-version`, `.sdkmanrc`, `rust-toolchain(.toml)`, `global.json`.
3. A pin inside the manifest: `package.json` `volta.node`.
4. A range or minimum: `package.json` `engines.node` and `devEngines.runtime` (the `version` of its `node` entry), `pyproject.toml` `requires-python` or `tool.poetry.dependencies.python`, and `go.mod` `go`, which is the minimum Go version, not a pin: any toolchain at or above it is valid. Choose a version for a range as in "Choosing inside a range" below.
5. CI only (`.github/workflows/*`, `setup-node`/`setup-python` `node-version`/`python-version`, or a matrix): use the version CI tests with, preferring the newest in a matrix.
6. Nothing pinned: use what the machine has, if it satisfies the manifests, and say in the summary that nothing was pinned.

`go.mod` `toolchain` names the preferred toolchain. It is not a pin in the list above: with `GOTOOLCHAIN=auto` the go command switches to it on demand when the local Go is older, and a newer local Go is also fine.

## Choosing inside a range

Most ranges are open-ended (`>=18`, `>=3.9`), so "the newest release" is often too new. Use the first that applies:

1. The installed version, if it satisfies the range and is not a Node odd-numbered (Current) line.
2. The version CI uses, if it is inside the range.
3. Node: the newest LTS release that satisfies the range, not an odd-numbered Current line, which never becomes LTS and which many native modules do not support. List the LTS releases (`nvm ls-remote --lts`, `fnm ls-remote --lts`, `mise ls-remote node`), pick the newest that satisfies the range, and install that version explicitly (`nvm install 22`). The bare LTS aliases (`nvm install --lts`, `mise install node@lts`) select the newest LTS overall, so use them only when that release satisfies the range (e.g. `>=18 <23` excludes Node 24).
4. Python: the newest minor inside the range for which the lockfile has wheels for the compiled dependencies (`uv.lock` and `poetry.lock` list wheel file names with tags such as `cp313`); without a lockfile, the newest minor before the latest release. A brand-new minor often lacks wheels, and building from source then fails on compilers and headers for a reason that is only the version choice.

Nothing pinned this choice, so record it in the summary as a decision, with the reason.

Partial pins (`20`, `3.12`, `lts/*`, `lts/iron`) mean "latest matching". Resolve them through the version manager (`nvm install 20`, `uv python install 3.12`, `mise install node@20`); do not hard-code a patch version yourself.

## Verifying the active version

A version counts as in use only when the command that runs the tests sees it. Check in the same kind of shell you use for install and test, not just once after installing:

| Runtime | Check | Also check |
|---|---|---|
| Node | `node --version` | `command -v node` points into the manager's directory, not `/usr/bin` |
| Python (uv), before `uv sync` | `uv python find` (the interpreter uv would use for this project) | its version satisfies the requirement |
| Python (uv), after `uv sync --locked` | `uv run --no-sync python --version` | `uv run --no-sync python -c 'import sys; print(sys.prefix)'` is the project `.venv` |
| Python (venv/poetry/pdm) | `.venv/bin/python --version`, `poetry run python --version`, `pdm run python --version` | same `sys.prefix` check |
| Go | `go version` inside the repository (with `GOTOOLCHAIN=auto`, this may switch to the `toolchain` line and download it, so run it in step 3, not in the survey) | `go env GOTOOLCHAIN` |
| Rust | `rustc --version` inside the repository (rustup reads the toolchain file there) | `rustup show active-toolchain` |
| Java | `java -version` and the build tool's view (`./gradlew -version`, `./mvnw -v`) | `JAVA_HOME` |

Compare the result with the requirement:

- Exact pin: major.minor (and patch, when the pin has one) must match.
- Range or minimum (including `go.mod` `go`): the active version satisfies it; a newer version is not a mismatch.
- Record "required", "source", "active" and "matches" for each runtime in the summary.

Never use plain `uv run` for a check: it locks and syncs the project first, so with a stale `uv.lock` it rewrites the lockfile and hides the problem the locked install would report. Project environments (`.venv`) exist only after the dependency install, so check the interpreter before it and the environment after it.

If the versions do not match after setup, do not continue to the tests as if they did. Fix the activation (see `references/environments.md`), or report the mismatch as a blocker.
