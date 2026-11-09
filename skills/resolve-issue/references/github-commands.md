# GitHub commands for the orchestrator

Read when you check an issue's dependencies, look for an existing PR, or wait for CI. Agents do their own GitHub work; these commands are only for your reads. `gh` subcommands such as `gh pr checks` use GraphQL, which some environments reject with HTTP 403. The REST forms (`gh api repos/...`) work there too.

## Issue and dependencies

```bash
# Body (read "Depends on" and similar sections)
gh api "repos/${repo:?}/issues/${issue:?}" --jq '{number, title, state, body}'
# Sub-issues
gh api "repos/${repo:?}/issues/${issue:?}/sub_issues" --jq '.[] | {number, title, state}'
# Issues this one is blocked by
gh api "repos/${repo:?}/issues/${issue:?}/dependencies/blocked_by" --jq '.[] | {number, title, state}'
```

## Existing PR for an issue

Look for open PRs that reference the issue in the issue's timeline. A PR whose body says `Closes #<issue>` appears there as a cross-reference:

```bash
gh api --paginate "repos/${repo:?}/issues/${issue:?}/timeline" \
  --jq '.[] | select(.event == "cross-referenced" and .source.issue.pull_request != null and .source.issue.state == "open")
        | .source.issue | {number, title, html_url}'
```

Then confirm the PR's state and head:

```bash
gh api "repos/${repo:?}/pulls/${pr:?}" --jq '{number, state, merged, draft, head_sha: .head.sha, head_ref: .head.ref, body}'
```

## Waiting for CI

Run one command in the background that ends when CI ends. The command loops by itself, so waiting spends no turns; you are woken once, by its completion notification.

```bash
gh pr checks "${pr:?}" --repo "${repo:?}" --watch --interval 30
```

Without GraphQL, loop over the head commit's check runs instead:

```bash
sha=$(gh api "repos/${repo:?}/pulls/${pr:?}" --jq .head.sha)
while gh api --paginate "repos/${repo:?}/commits/${sha:?}/check-runs" --jq '.check_runs[] | .status' | grep -qv completed; do
  sleep 30
done
gh api --paginate "repos/${repo:?}/commits/${sha:?}/check-runs" \
  --jq '.check_runs[] | {name, conclusion, html_url}'
```

A check run with a `conclusion` other than `success`, `neutral` or `skipped` is a failure to pass to the implementer. Include each failing check's name and URL.
