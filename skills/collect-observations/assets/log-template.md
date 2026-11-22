## Goal

Keep a log of observations that reviewers and implementers noted during <scope> but did not raise as findings (out of scope, no current effect, nice to have), so they are not lost in agent reports and can be decided on later. Nothing here is planned work until its status says so.

## Scope

**How to use**
- The comments below copy each PR's observations comment, grouped by PR and by the SHA the items were reported at. Each item has:
  - item ID `#<PR>-<n>`, `file:line`, and the SHA it was reported at (in the PR heading)
  - Observation, Not raised because, Related (future issue or milestone, or none), Source (reviewer or implementer)
- Each item has a row in the status table below. Update the status when a decision is made.

**Status**

| Item | Summary | Status |
|---|---|---|
| [#<PR>-<n>](<log comment URL>) | <short summary> | open |

Status values: `open`, `issue #N`, `in #N` (folded into another issue), `dropped (reason)`, `moved to <next log>`.

**PRs with no observations**: PR #<PR>, PR #<PR>

## Out of scope

- Acting on any item here. Each change needs its own issue or a place in an existing issue.
- Findings raised in reviews; those are tracked in the PR threads.

## Acceptance criteria

- Before closing (<when the log closes, e.g. at the end of the milestone>), every row must have a status other than `open`. Items still undecided can be marked `moved to` the next log with a link.
- `triage-observations` may close this log as completed when every row is decided and the user approves closing it.

## Depends on

- None

Part of #<parent issue number>.

<!-- collect-observations:log -->
