# Running Codex

Read before starting or resuming a Codex agent. Codex runs non-interactively with `codex exec`. Run it from the target repository's checkout with the Bash tool's background mode, and wait for the completion notification.

## Files

Keep each run's files in a scratch directory outside the repository, so they are never committed:

- the prompt
- the JSONL event stream (`--json`)
- the final message (`-o`)
- stderr

Use a new set of file names for every run, so a resume cannot overwrite the first run's record. Write the prompt to its file with the Write tool, not with shell quoting. Handoffs contain apostrophes and `$agent-skills:...`, which break quoted strings or get expanded by the shell.

## First run

```bash
cd "${repo_checkout:?}" && codex exec --json -o "${last_message:?}" - \
  < "${prompt_file:?}" > "${events:?}" 2> "${stderr_file:?}"
```

`-` reads the prompt from stdin, which is the prompt file. Do not leave stdin unredirected: on a stdin that is not a terminal, `codex exec` waits for more input.

After the completion notification, read the thread ID from the first event:

```bash
head -1 "${events:?}" | jq -r 'select(.type == "thread.started") | .thread_id'
```

## Resume

```bash
cd "${repo_checkout:?}" && codex exec resume --json -o "${last_message:?}" "${thread_id:?}" - \
  < "${prompt_file:?}" > "${events:?}" 2> "${stderr_file:?}"
```

Always pass the recorded ID. `--last` picks the most recent session, which may belong to another task.

## Reading the result

- The final report is the `-o` file. Read it and the exit status.
- If the run failed or the file is empty, read the end of stderr and the last events; `turn.completed` carries token usage.
- Treat the report as the agent's account. Check a claim that decides your next step, such as the PR number or CI state, with `gh` (`github-commands.md`) before acting on it.
