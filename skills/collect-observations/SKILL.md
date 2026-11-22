---
name: collect-observations
description: Collect the observations comments that orchestrate-issue posted on merged PRs into one log issue (a status table plus copied items), creating the log or appending to an existing one and skipping PRs already collected. Targets are PR or issue numbers, an issue's sub-issues or a milestone (e.g. 「observationをまとめて」「M2のobservationをログにして」「#40〜#45のobservationを#32に追記して」). Use triage-observations to decide or file log items and orchestrate-issue to post a PR's observations.
---

# collect-observations

Gather the observations that `orchestrate-issue` recorded on PRs into one log issue, so they can be decided on in one place. Each run copies only PRs that are not collected yet, so the same item never appears twice in a log.

Commands, with REST forms that work where GraphQL returns HTTP 403, are in `references/github-commands.md`. The log's comments, body and markers are in `references/log-format.md`; read it before writing anything.

## Arguments

- Targets, one or more of: PR numbers, issue numbers (their merged PRs), sub-issues of an issue, a milestone. Optionally `OWNER/REPO`; else the current repository.
- `--log <issue>`: append to that log. Without it, create a new log.

## Rules

- Write only to the log issue: create it, post comments on it, update its body. Never comment on, edit or react to the PRs or their comments. The cross-reference GitHub adds when a log comment mentions a PR already links the PR to the log.
- Copy items as they are ("Log comment" in `references/log-format.md`). Never rewrite, merge or drop an item, and never fill in a field the source left empty.
- Every new status row is `open`. Never decide an item or change an existing row: those are the user's decisions. Use `triage-observations` to recommend decisions for log items and file approved items as issues.
- The log lives in the same repository as the PRs, because `#<PR>` references and item IDs only mean something there. Targets in several repositories need one log each.
- Post nothing before the user approves the plan (step 3), because the log is shared with everyone who reads the repository.

## Workflow

1. **Resolve the targets to PRs** ("Resolving the targets" in `references/github-commands.md`). Keep the list of PR numbers, and the issues with no merged PR, for the plan.
2. **Scan.** Run `scripts/scan.sh` with the PRs (and `--log`, if given). It reports each PR's `status`:

   | `status` | Meaning | Next |
   |---|---|---|
   | `uncollected` | Merged, with an observations comment not in any log | Collect |
   | `partial` | Some of its observations comments are in a log | Collect the rest |
   | `collected` | Every observations comment is in a log (`collected` says where) | Skip |
   | `no-comment` | Merged, but no observations comment: not run through `orchestrate-issue`, or posted before it recorded observations | Skip; list in the plan |
   | `not-merged` | Not merged; `orchestrate-issue` posts only after the merge | Skip; list in the plan |

   A PR in `unmarked_mentions` is mentioned by an issue without the log marker. Most are ordinary issues; one that looks like a log (e.g. its title says "observations log") was written by hand or before this skill, and may already hold the PR's items. Name it in the plan.

   Without `--log`, also look for open logs ("Existing logs").

   Then check for leftovers of an earlier run: in the `--log` issue and in every log `scan.sh` names under `collected`, compare the marked comments with the body ("Leftovers" in `references/log-format.md`). A run that posted comments but failed to update the body leaves its PRs `collected` with no rows, and only this check finds them.
3. **Plan.** Show the user, and wait for approval:
   - The log: a new log (title, labels, milestone, parent), or the issue to append to, and whether its body needs the log marker.
   - The PRs to collect, with the number of items in each.
   - The PRs skipped, by status, with where each collected one is.
   - Leftovers to repair: missing rows and missing PRs on the no-observations line, per log.
   - Issues with no merged PR, sub-issues in other repositories, logs that look hand-written, and open logs found without `--log`.

   Repairs go to the log that holds the leftover, which may not be the log this run writes to. With nothing to collect, the plan names no log to create or append to and lists only the repairs: a new log would stay empty. If there is nothing to collect or repair, report that and stop.
4. **Create the log** (new log with PRs to collect only) from `assets/log-template.md`, with only the status table's header rows, so the comments have an issue to go to. Note its number and URL.
5. **Post the log comments** ("Log comment" in `references/log-format.md`). Before posting, and before retrying a failed post, read the log's comments for the source markers you are about to post; skip a PR whose marker is already there. A lost response can hide a post that succeeded.
6. **Update the body** with a row for each new item, linking the comment that holds it, the new PRs with no observations, and the leftovers ("Log body", "Status rows" and "Leftovers" in `references/log-format.md`). Write each leftover into the body of the log that holds it. A repair-only run skips steps 4 and 5. Read the body again right before you write it.

If a post fails, stop and report what was posted, with the error. A later run picks up from the markers: a PR whose comment was posted is skipped, and its missing rows are found as leftovers.

## Language

- The log's prose (the template text, Summary cells, the no-observations line) follows the target repository's language (its existing issues, PRs and comments), else the user's language. Section headings stay in English.
- Copied items stay in the language they were posted in. Keep the markers, item IDs, paths and SHAs as they are, so they still match.
- The plan and the final report are in the user's language.

## Final report

- The log URL, and whether it was created or appended to.
- Each log comment's URL and the PRs and number of items in it.
- The skipped PRs by status, issues with no merged PR, and anything that failed, with the error.
- A reminder that every new row is `open`, waiting for the user's decision.
