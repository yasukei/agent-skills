# Observations

Read before writing the final report. Observations are what an agent noticed but did not raise as a finding or include in the PR. Report them in this fixed format, so the user can paste them into a log issue and decide on each later without asking the agents again.

## Fields

| Field | Content |
|---|---|
| PR | The PR number |
| SHA | The head the reporting agent had checked when it reported the item: the reviewer's head at that review or re-check, or the implementer's head when it reported. The line numbers refer to this SHA |
| `file:line` | One or more locations. A file without a line when the observation is about the whole file |
| Observation | What was noticed |
| Not raised because | Why it was not a finding or part of the PR, e.g. out of the issue's scope, no current effect, nice to have |
| Related issue or milestone | A future issue or milestone it belongs to, or `unknown` |
| Source | `reviewer` or `implementer` |

The handoffs ask the agents for these fields ("Final report" lines in `handoffs.md`).

## Missing fields

- `file:line` and the related issue or milestone: if the agent did not report them, you may fill them, so the user does not have to look them up. Look up a line at the group's SHA, not at the worktree's current head, which has usually moved on (e.g. `git -C <worktree> grep -n <pattern> <SHA>`). Find issues and milestones with "Issues and milestones" in `github-commands.md`. Mark each value you filled with `(filled in by the orchestrator)`, so the user can tell it from what the agent reported. If you cannot fill it, write `unknown`.
- Not raised because: never guess it. Write that it was not reported. A guessed reason looks like the agent's judgment and can lead the user to drop an item for a reason nobody gave.
- Any other field the agent did not report: write that it was not reported.

## Grouping

Group the items by PR, with the PR number and SHA in the group heading, so they are not repeated in every item. Items reported at different SHAs go into separate groups, one per SHA. This is the normal case for a PR with fixes: the implementer's first report, the first review and each re-check usually see different heads.

## Language

The final report is in the user's language. Field names may be translated; keep each item's content as defined above. Translate the agents' English prose without changing its meaning, but keep paths, identifiers, SHAs and issue references as they are, so they still link and match the code.

## Template

```markdown
### PR #<number> at <SHA>

- `<file>:<line>`, `<file>`
  - Observation: <what was noticed>
  - Not raised because: <reason, or "not reported">
  - Related issue or milestone: <#issue, milestone, or unknown>
  - Source: <reviewer or implementer>

### PR #<number> at <later SHA>

- ...
```

If no agent reported an observation for an issue, say so in one line instead of leaving the section out, so the user can tell "none" from "forgotten".
