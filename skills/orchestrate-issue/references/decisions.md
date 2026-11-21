# Questions from agents

Read when the implementer or reviewer stops with a question or a choice. Classify it, then handle it by its type. `--delegate` never covers type A: the underlying skills ask because those decisions belong to the user, and an answer from you would look like the user's approval.

| Type | Examples | Without `--delegate` | With `--delegate` |
|---|---|---|---|
| A: always the user's | Merging without `--merge`. Irreversible actions (force push, deleting branches or worktrees, closing issues). Changes to permissions, sandboxes or credentials. Work outside the issue. Breaking or public API changes. Contradictions in the issue itself. Disagreement between implementer and reviewer. Anything the underlying skill says needs the user's explicit authorization, such as resolving threads from another or unknown session, running fork PR code, or reviewing a draft or closed PR | Ask the user | Ask the user |
| B: a design choice with a recommendation | Within the issue's scope, reversible, and the agent states a recommendation, e.g. two ways to address a finding | Ask the user, with the recommendation | Take the recommendation, and record it |
| C: procedural | How to proceed within the workflow, e.g. which existing artifact to point an agent to | Decide and report it | Decide and report it |

Treat a B question as A when the recommendation conflicts with the issue's acceptance criteria or the repository's instructions (e.g. `AGENTS.md`, `CLAUDE.md`), or when there is no recommendation.

## Asking the user

Put the question in one message that the user can answer without scrolling back. Include:

- the issue and PR
- what the agent asked, in short
- the options, with the agent's recommendation and yours

Agents ask in English ("Language" in `handoffs.md`); ask the user in the user's language. Translate without changing the meaning: keep every option the agent gave and its reason for the recommendation. A dropped option or reason changes the choice the user makes.

## Taking a recommendation under `--delegate`

1. Check the recommendation against the issue and the repository's instructions.
2. Resume the agent with the wording in `handoffs.md` ("Answering a question"), so its records say who chose it.
3. Add it to the final report: the question, the options, the chosen one, and how to reverse it.
