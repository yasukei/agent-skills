# Python projects

Never install the project's dependencies into the system Python (`pip install` without a virtual environment, `--break-system-packages`): it changes the machine for every project and is blocked by PEP 668 on most distributions. Every manager below creates a project environment.

## Choosing the tool

Use the first that applies: the repository's instructions, then the lockfile (`uv.lock` → uv, `poetry.lock` → poetry, `pdm.lock` → pdm, `Pipfile.lock` → pipenv), then `pyproject.toml` `[build-system]`/`[tool.*]` sections (`tool.poetry`, `tool.pdm`, `tool.hatch`), then plain `requirements*.txt` (venv + pip). When the project uses tox or nox, CI usually runs tests through them; follow CI.

The tool itself is missing:

- With `pipx` present: `pipx install uv` (or `poetry`, `pdm`, `pipenv`).
- With uv present and another tool needed: `uv tool install poetry`.
- Otherwise `python3 -m pip install --user <tool>` if pip is allowed there, or ask before using an installer script (`curl -LsSf https://astral.sh/uv/install.sh | sh`).

## Installing the Python version

| Tool | Install | Notes |
|---|---|---|
| uv | `uv python install` (reads `.python-version`; or `uv python install 3.12`) | `uv sync` also downloads a matching Python when `python-downloads` is allowed. Downloads come from GitHub releases, which a firewall may block |
| pyenv | `pyenv install -s <version>` (reads `.python-version` with no argument) | then `pyenv local` is not needed; `.python-version` already selects it |
| mise / asdf | `mise install` / `asdf install python <version>` | |
| poetry | `poetry env use <path-or-version>` after installing that Python with one of the above | |

A system Python that satisfies `requires-python` may be used when nothing pins an exact version.

## Installing dependencies

| Tool | Command | Check |
|---|---|---|
| uv | `uv sync --locked` (add `--all-extras` / `--all-groups` only when CI does) | `uv run --no-sync python --version` |
| poetry | `poetry check --lock && poetry install` (add `--with <group>` / `--all-extras` as CI does) | `poetry run python --version` |
| pdm | `pdm sync` (installs from the lock without updating it) | `pdm run python --version` |
| pipenv | `pipenv sync --dev` | `pipenv run python --version` |
| hatch | environments are created on demand by `hatch test` / `hatch run` | `hatch run python --version` |
| pip | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt` (or `-e '.[dev]'`, or `--group dev` with pip 25.1+) | `.venv/bin/python --version` |

- If the lockfile is out of date (`uv sync --locked` or `poetry check --lock` fails), report it; do not run `uv lock` / `poetry lock`, which rewrite a tracked file.
- With uv, always pass `--no-sync` to `uv run` (or set `UV_NO_SYNC=1`). Plain `uv run` locks and syncs first, which rewrites a stale `uv.lock`.
- Packages that build from source need a compiler and headers (`python3-dev`, `libpq-dev`, ...). Missing system packages need the system package manager; ask first.
- Keep the environment inside the repository (`.venv`) unless the tool's configuration says otherwise, and check that it is ignored by git.

## Running the tests

- Use the command CI runs, else the tool's runner: `uv run --no-sync pytest`, `poetry run pytest`, `pdm run pytest`, `hatch test`, `.venv/bin/python -m pytest`, `tox -e <env>`, `nox -s tests`.
- Plain `pytest` on PATH may be another environment's; run it through the project environment.
- `python -m unittest discover` when there is no pytest configuration and tests use unittest.
