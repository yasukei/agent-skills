---
name: triage-observations
description: Triage open items in a collect-observations log, recommend decisions, and file approved work and update the log. Use for observation triage or an approved retry. Use collect-observations to build a log and create-issue to file standalone issues.
---

# triage-observations

Recommend a decision for each selected open observation and record only the decisions the user approves.

## Arguments

- A log issue as `#<n>`, `OWNER/REPO#<n>` or a GitHub issue URL. A bare issue number uses the current repository.
- Optionally, item IDs such as `#40-1 #41-2` to limit the run. Report requested IDs that are absent or already decided.

## Rules

- Post nothing before the user approves the plan. Issues and comments are public in public repositories and can notify people. The user may change any decision or approve only some items.
- Write in the log's repository. Create the approved issues, add approved comments to existing issues, and update only the Status cells of approved log rows. Leave all other rows and the rest of the log intact. Log closure is the user’s decision.
- Link each issue and fold comment to its log items and include their retry marker. Never edit a fold target's body or comment on, edit or react to the source PRs.
- Follow the target repository's language for issue and comment prose, else the user's language. Use the user's language in chat. Preserve IDs, SHAs, URLs and marker syntax.

## Workflow

1. **Read.** Resolve the log host, repository and number and run `scripts/read-log.py OWNER/REPO ISSUE --hostname HOST`. See `references/github-commands.md` for GitHub reads and writes, including REST alternatives. Work from rows with status `open` and the items in their linked log comments. Stop if the log cannot be read. If no selected rows are open, report that and stop.
2. **Decide.** Read `references/decisions.md`. For each item, inspect the cited code at its recorded SHA, look up its Related field, and search open and closed issues in the log repository. Check for earlier posts with the retry marker before drafting. Recommend one of new issue, fold into an open issue, drop, or keep open, with a one-line reason. Group items only when one issue can cover all their acceptance criteria.
3. **Plan and self-check.** Read `references/formats.md` to prepare the plan. Show every selected open item and its reason, the exact issue titles and bodies, the exact fold comments and targets, and each row's proposed status. Show earlier posts you would reuse. Check the plan yourself before presenting it:
   - Every selected open item has exactly one decision.
   - Each drafted issue has verifiable acceptance criteria.
   - No drafted issue duplicates an existing one or another draft.
   - Every proposed Status cell uses the log's existing values.
4. **Wait for approval.** If the user changes anything, show the resulting titles, bodies, comments and statuses for approval before posting them. On partial approval, trim grouped posts to the approved items and confirm any resulting changes to their content.
5. **Execute.** Recheck that rows are still open and the approved posts still match the items and targets. Apply the retry checks in `references/github-commands.md`. Use the actual issue numbers from successful or recovered posts. When ready to update the log, read its body again immediately before writing, and change only the approved Status cells whose rows are still open and match the plan. Report rows that changed. Skip the body update if nothing needs changing.
6. **Report.** Give the log URL, decisions and resulting statuses by item ID, the new or reused issue and comment URLs, and any failures or rows still open. On failure, stop and say which effects were verified and which remain uncertain. A retry uses the markers to recover posts before proposing any remaining changes.
