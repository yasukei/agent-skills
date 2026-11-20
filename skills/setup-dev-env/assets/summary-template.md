## Development environment setup: <repository>

**Result:** <Ready: all tests pass | Ready with known failures | Blocked: <one-line reason>>

### Environment
- Kind: <sbx sandbox `<name>` (direct/clone mode) | host <OS> | cloud>
- Shell used: <bash / zsh / PowerShell>

### Runtimes
| Runtime | Required | Source | Active | Matches |
|---|---|---|---|---|
| Node | 20.x | `.nvmrc` | v20.11.1 (nvm) | ✅ |
| Python | >=3.11 | `pyproject.toml` requires-python | 3.12.4 (`.venv`, uv) | ✅ |

<Disagreements between pin sources, if any.>

### Tools and dependencies
| Tool | Version | How it was obtained | Install command | Result |
|---|---|---|---|---|
| pnpm | 9.1.0 | corepack (`packageManager`) | `pnpm install --frozen-lockfile` | ✅ 812 packages |
| uv | 0.13.9 | already installed | `uv sync --locked` | ✅ |

### Tests
| Command | Result | Notes |
|---|---|---|
| `CI=true pnpm test` | ✅ 214 passed | |
| `uv run pytest` | ❌ 2 failed / 98 passed | `test_x` looks like a code bug: <one line> |

### Changes made
- Outside the repository: <installed Node 20.11.1 with nvm; appended 2 lines to `/etc/sandbox-persistent.sh`; none>
- Inside the repository (untracked/ignored only): <`node_modules/`, `.venv/`, `.env` copied from `.env.example`>
- Tracked files: <none | what changed and why it was not reverted>

### Not done / needs you
- <e.g. `NPM_TOKEN` for the private registry; approve `objects.githubusercontent.com`; e2e tests skipped (need a browser and sudo)>

### Rerun
```bash
<the commands to activate the environment and run the tests again from a fresh shell>
```
