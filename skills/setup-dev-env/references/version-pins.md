# Deciding the required runtime version

`scripts/detect.sh` prints every pin it finds, one line per source. Use this file to decide which version to install and to check that it is the one in use.

## Precedence

When sources disagree, use the first that applies, and report the disagreement in the summary (it is usually a bug in the repository, not something to fix during setup):

1. The repository's own setup instructions (README, CONTRIBUTING, AGENTS.md, devcontainer), when they name a version.
2. An exact pin file read by version managers: `.nvmrc`, `.node-version`, `.python-version`, `.tool-versions`, `mise.toml` `[tools]`, `.ruby-version`, `.java-version`, `.sdkmanrc`, `rust-toolchain(.toml)`, `global.json`, `go.mod` `toolchain`.
3. A pin inside the manifest: `package.json` `volta.node` or `devEngines.runtime`, `go.mod` `go`.
4. A range: `package.json` `engines.node`, `pyproject.toml` `requires-python` or `tool.poetry.dependencies.python`. Pick the version CI uses if CI is inside the range, else the newest stable release inside the range that the version manager offers.
5. CI only (`.github/workflows/*`, `setup-node`/`setup-python` `node-version`/`python-version`, or a matrix): use the version CI tests with, preferring the newest in a matrix.
6. Nothing pinned: use what the machine has, if it satisfies the manifests, and say in the summary that nothing was pinned.

Partial pins (`20`, `3.12`, `lts/*`, `lts/iron`) mean "latest matching". Resolve them through the version manager (`nvm install 20`, `uv python install 3.12`, `mise install node@20`); do not hard-code a patch version yourself.

## Verifying the active version

A version counts as in use only when the command that runs the tests sees it. Check in the same kind of shell you use for install and test, not just once after installing:

| Runtime | Check | Also check |
|---|---|---|
| Node | `node --version` | `command -v node` points into the manager's directory, not `/usr/bin` |
| Python (uv) | `uv run python --version` | `uv run python -c 'import sys; print(sys.prefix)'` is the project `.venv` |
| Python (venv/poetry/pdm) | `.venv/bin/python --version`, `poetry run python --version`, `pdm run python --version` | same `sys.prefix` check |
| Go | `go version` (with `GOTOOLCHAIN` auto, the go.mod toolchain is downloaded on demand) | `go env GOTOOLCHAIN` |
| Rust | `rustc --version` inside the repository (rustup reads the toolchain file there) | `rustup show active-toolchain` |
| Java | `java -version` and the build tool's view (`./gradlew -version`, `./mvnw -v`) | `JAVA_HOME` |

Compare the result with the requirement:

- Exact pin: major.minor (and patch, when the pin has one) must match.
- Range: the active version satisfies the range.
- Record "required", "source", "active" and "matches" for each runtime in the summary.

If the versions do not match after setup, do not continue to the tests as if they did. Fix the activation (see `references/environments.md`), or report the mismatch as a blocker.
