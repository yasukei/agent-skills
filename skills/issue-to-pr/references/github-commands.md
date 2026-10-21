# GitHub commands

Commands for each step of SKILL.md, and their REST replacements when GraphQL is not available.

## When GraphQL is not available

In some environments, such as Claude Code on the web, the GitHub GraphQL API is rejected with `HTTP 403: GitHub GraphQL is not available ...`. Every `gh` command that uses GraphQL internally then fails: `gh issue view`, `gh pr list`, `gh repo view`, `gh pr create`, `gh pr comment`, `gh pr edit`, `gh pr view` and `gh pr checks`. Replace them with REST calls through `gh api` (`gh api repos/...`, `gh pr diff` and `gh run ...` still work).

| Purpose | Normal | Without GraphQL |
|---|---|---|
| Read an issue | `gh issue view <number> --comments` | `gh api repos/{owner}/{repo}/issues/<number>` and `gh api --paginate "repos/{owner}/{repo}/issues/<number>/comments?per_page=100"` |
| Recent PRs | `gh pr list --state all --limit 10` | `gh api "repos/{owner}/{repo}/pulls?state=all&per_page=10" --jq '.[] \| {number, title}'` |
| Default branch | `gh repo view --json defaultBranchRef` | `gh api repos/{owner}/{repo} --jq .default_branch` |
| Create a PR | `gh pr create ...` | `gh api repos/{owner}/{repo}/pulls -X POST -f title="<title>" -f head=<branch> -f base=<base branch> -F body=@<body file> --jq .html_url` |
| Comment on a PR | `gh pr comment <PR number> --body "..."` | `gh api repos/{owner}/{repo}/issues/<PR number>/comments -X POST -f body="..."` |
| Get the PR title and body | `gh pr view <PR number> --json title,body` | `gh api repos/{owner}/{repo}/pulls/<PR number> --jq '{title, body}'` |
| Update the PR title and body | `gh pr edit <PR number> --title "<title>" --body-file <body file>` | `gh api repos/{owner}/{repo}/pulls/<PR number> -X PATCH -f title="<title>" -F body=@<body file>` |
| Monitor the PR | `scripts/pr_status.sh` | Works as is (on a GraphQL 403 it switches to REST and the CCR route for review threads) |

- `gh api` replaces `{owner}/{repo}` with the repository of the current directory.
- `-F body=@<file>` uses the file's contents as the body.
- On the REST path of `scripts/pr_status.sh`, `reviewDecision` and `threads[].id` (the GraphQL thread ID) are `null`. This does not affect `verdict`.
- With an old `gh` whose `gh pr checks` has no `--json` (such as 2.46), `scripts/pr_status.sh` gets only the CI state through REST.

## Before implementing

```bash
gh issue view <number> --comments                # read the issue and its comments
git log --oneline -20                            # language and style of existing commits
gh pr list --state all --limit 10                # language and style of existing PRs
gh repo view --json defaultBranchRef             # base branch
```

## Creating the PR

```bash
git push -u origin <branch>
gh pr create --base <base branch> --title "<title>" --body-file <body file>
```

## Monitoring

```bash
scripts/pr_status.sh <PR number> [owner/repo]    # CI, reviews, threads and verdict as JSON
gh run view <run-id> --log-failed                # logs of the failed jobs
gh run rerun <run-id> --failed                   # re-run the failed jobs once (suspected flaky)
git merge origin/<base branch>                   # resolve a conflict by merging, never rebase
```

## Replying to review comments

End every comment with the marker `<!-- issue-to-pr -->` (see `review-protocol.md`).

```bash
# Reply to an inline review comment (thread)
gh api repos/{owner}/{repo}/pulls/<PR number>/comments/<comment_id>/replies -f body="...

<!-- issue-to-pr -->"

# Comment on the whole PR, or reply to a review body
gh pr comment <PR number> --body "...

<!-- issue-to-pr -->"
```

## Updating the PR title and body

Fetch the current title and body from the PR, not from the local file used at creation, because it may be stale or someone may have edited it on GitHub.

```bash
gh pr view <PR number> --json title,body
gh pr edit <PR number> --title "<title>" --body-file <body file>
```
