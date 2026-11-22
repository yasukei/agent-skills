# GitHub commands for the orchestrator

Read when you check an issue's dependencies, look for an existing PR, wait for CI, check for a conflict, fill in an observation's related issue or milestone, confirm a merge, or look for and post the observations comment. Agents do their own GitHub work; apart from that one comment, these commands are only for your reads. `gh` subcommands such as `gh pr checks` use GraphQL, which some environments reject with HTTP 403. The REST forms (`gh api repos/...`) work there too.

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

Run `scripts/wait_ci.sh` once in the background. It loops by itself, so waiting spends no turns and its completion notification wakes you once. It reads check runs and commit statuses through REST, so it works where GraphQL returns HTTP 403, and it covers CI that reports only commit statuses. It checks mergeability during the wait and again when CI finishes. It returns as soon as GitHub reports a conflict because a conflicting PR may register no CI.

```bash
"${skill_dir:?}/scripts/wait_ci.sh" "${pr:?}" "${repo:?}"
```

`skill_dir` is this skill's absolute directory. The script prints one JSON line with the head `sha`, `state`, `mergeable`, and `failing` checks.

| `state` | Exit | Meaning | Next |
|---|---|---|---|
| `success` | 0 | Every check run and status passed | Continue |
| `failure` | 1 | `failing` lists each failed check's name and URL | Pass them to the implementer |
| `none` | 0 | Nothing was registered within 5 minutes; the repository may have no CI | Continue, and mention it in the final report |
| `timeout` | 3 | Still running after 60 minutes | Ask the user |
| `conflicting` | 4 | `mergeable` is `false`, regardless of CI | Follow `conflicts.md` |
| `mergeability_timeout` | 3 | `mergeable` is still `null` after retries | Stop and ask the user |

Exit 2 means a usage error, a GitHub API error, or a change to the PR head since the wait began. Report it before continuing. For a changed head, start a fresh wait to get CI and mergeability for the same commit.

The script waits for the PR's head when it starts. Start it after the implementer has pushed, not while the implementer is still working.

## Checking for a conflict

Use this mode at the checkpoints in `conflicts.md` that do not need a CI wait. Run it in the background for the same completion notification.

```bash
"${skill_dir:?}/scripts/wait_ci.sh" "${pr:?}" "${repo:?}" --mergeability-only
```

The script reads `gh api "repos/${repo:?}/pulls/${pr:?}"`. Only `mergeable: false` indicates a conflict, typically with `mergeable_state: dirty`. States such as `behind` and `blocked` do not indicate a conflict. GitHub returns `mergeable: null` while computing it, so the script retries up to five total reads, two seconds apart by default. If it stays `null`, the result is `mergeability_timeout`.

This mode returns `no_conflict` with exit 0 when `mergeable` is `true`. The `conflicting`, `mergeability_timeout`, and exit 2 outcomes are as above. Use this result only for mergeability. The mode does not query CI.

## PR state

To confirm the merge before posting the observations comment (`observations.md`) and before the implementer's cleanup (`cleanup.md`):

```bash
gh api "repos/${repo:?}/pulls/${pr:?}" --jq '{number, state, merged, merge_commit_sha}'
```

## Finding the observations comment

Before posting, and before retrying a failed post, look for a comment that already carries the marker. An empty result means none was posted:

```bash
gh api --paginate "repos/${repo:?}/issues/${pr:?}/comments" \
  --jq '.[] | select(.body // "" | contains("<!-- orchestrate-issue:observations -->")) | {id, html_url, created_at}'
```

## Posting the observations comment

Generate the signature once into `SIG_FILE`, a file outside the repository (e.g. from `mktemp`). Pass `--model` only with the model ID your own instructions state, and `--effort` only if they state one; never guess:

```bash
"${skill_dir:?}/scripts/signature.sh" --agent claude-code --model MODEL_ID > SIG_FILE
```

Write the body to `BODY_FILE` with a quoted heredoc, so backticks and `$` in it stay as they are. Append a blank line, the signature and the marker, and post it through REST, which works where GraphQL returns HTTP 403:

```bash
cat > BODY_FILE <<'EOF'
### PR #123 (issue #45) — at 1a2b3c4
...
EOF
{ echo; cat SIG_FILE; echo '<!-- orchestrate-issue:observations -->'; } >> BODY_FILE
gh api "repos/${repo:?}/issues/${pr:?}/comments" -X POST -F body=@BODY_FILE --jq .html_url
```

Read `SIG_FILE` in the post rather than a shell variable: variables do not survive between tool calls, and an empty one posts an unsigned comment without any error.
