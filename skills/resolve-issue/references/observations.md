# Observations

Read before writing the final report. Observations are what an agent noticed but did not raise as a finding or include in the PR. Report them in this fixed format, so the user can paste them into a log issue and decide on each later without asking the agents again.

## Fields

| Field | Content |
|---|---|
| PR | The PR number |
| SHA | The head the PR was checked at: the reviewer's last checked head, or the implementer's head when it reported |
| `file:line` | One or more locations. A file without a line when the observation is about the whole file |
| Observation | What was noticed |
| Not raised because | Why it was not a finding or part of the PR, e.g. out of the issue's scope, no current effect, nice to have |
| Related issue or milestone | A future issue or milestone it belongs to, or `unknown` |
| Source | `reviewer` or `implementer` |

The handoffs ask the agents for these fields ("Final report" lines in `handoffs.md`).

## Missing fields

- `file:line` and the related issue or milestone: if the agent did not report them, you may fill them from the agent's worktree or the repository's issue list, so the user does not have to look them up. Otherwise write `unknown`.
- Not raised because: never guess it. Write that it was not reported. A guessed reason looks like the agent's judgment and can lead the user to drop an item for a reason nobody gave.
- Any other field the agent did not report: write that it was not reported.

## Grouping

Group the items by PR, with the PR number and SHA in the group heading, so they are not repeated in every item. If one PR's items were checked at different SHAs (e.g. the implementer's report and a later re-check), use one group per SHA.

## Language

The final report is in the user's language. Field names may be translated; keep each item's content as defined above. Keep paths, identifiers, SHAs and issue references as they are, so they still link and match the code.

## Template

```markdown
### PR #<number> at <SHA>

- `<file>:<line>`, `<file>`
  - Observation: <what was noticed>
  - Not raised because: <reason, or "not reported">
  - Related issue or milestone: <#issue, milestone, or unknown>
  - Source: <reviewer or implementer>
```

If no agent reported an observation for an issue, say so in one line instead of leaving the section out, so the user can tell "none" from "forgotten".
