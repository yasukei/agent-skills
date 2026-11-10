# GitHub commands for the orchestrator

Read when you check an issue's dependencies, look for an existing PR, wait for CI, or fill in an observation's related issue or milestone. Agents do their own GitHub work; these commands are only for your reads. `gh` subcommands such as `gh pr checks` use GraphQL, which some environments reject with HTTP 403. The REST forms (`gh api repos/...`) work there too.

## Issue and dependencies

```bash
# Body (read "Depends on" and similar sections)
gh api "repos/${repo:?}/issues/${issue:?}" --jq '{number, title, state, body}'
# Sub-issues
gh api "repos/${repo:?}/issues/${issue:?}/sub_issues" --jq '.[] | {number, title, state}'
# Issues this one is blocked by
gh api "repos/${repo:?}/issues/${issue:?}/dependencies/blocked_by" --jq '.[] | {number, title, state}'
```

## Issues and milestones

To fill in an observation's related issue or milestone (`observations.md`):

```bash
# Open issues (the endpoint also returns PRs; drop them)
gh api --paginate "repos/${repo:?}/issues?state=open&per_page=100" \
  --jq '.[] | select(.pull_request == null) | {number, title, milestone: .milestone.title}'
# Milestones
gh api --paginate "repos/${repo:?}/milestones?state=open&per_page=100" --jq '.[] | {number, title, description}'
```

## Existing PR for an issue

Candidates are open PRs in the same repository that the issue's timeline lists as cross-references. A PR in another repository can mention the issue too, and its number means nothing in this repository, so drop it:

```bash
gh api --paginate "repos/${repo:?}/issues/${issue:?}/timeline" | jq -s --arg repo "${repo:?}" '
  [.[][] | select(.event == "cross-referenced") | .source.issue
   | select(.pull_request != null and .state == "open"
            and .repository_url == "https://api.github.com/repos/" + $repo)
   | {number, title, html_url}]'
```

A mention does not make a PR the issue's implementation. Keep only a candidate whose body closes the issue (`Closes #<issue>`, `Fixes`, `Resolves`, also as `OWNER/REPO#<issue>`), as `issue-to-pr` writes it. Then confirm its state and head:

```bash
gh api "repos/${repo:?}/pulls/${pr:?}" | jq --arg repo "${repo:?}" --arg issue "${issue:?}" '
  {number, state, merged, draft, head_sha: .head.sha, head_ref: .head.ref,
   closes_issue: (.body // "" | test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?\\s+(" + $repo + ")?#" + $issue + "\\b"))}'
```

If no candidate closes the issue, treat the issue as having no PR. If more than one does, ask the user which one to continue.

## Waiting for CI

Run `scripts/wait_ci.sh` once in the background. It loops by itself, so waiting spends no turns; its completion notification wakes you once. It reads check runs and commit statuses through REST, so it works where GraphQL returns HTTP 403, and it covers CI that reports only commit statuses.

```bash
"${skill_dir:?}/scripts/wait_ci.sh" "${pr:?}" "${repo:?}"
```

`skill_dir` is this skill's absolute directory. The script prints one JSON line:

| `state` | Exit | Meaning | Next |
|---|---|---|---|
| `success` | 0 | Every check run and status passed | Continue |
| `failure` | 1 | `failing` lists each failed check's name and URL | Pass them to the implementer |
| `none` | 0 | Nothing was registered within 5 minutes; the repository may have no CI | Continue, and mention it in the final report |
| `timeout` | 3 | Still running after 60 minutes | Ask the user |

Exit 2 means a usage or GitHub API error, which is never read as "no CI". Report it instead of continuing.

The script waits for the PR's head when it starts. Start it after the implementer has pushed, not while the implementer is still working.
