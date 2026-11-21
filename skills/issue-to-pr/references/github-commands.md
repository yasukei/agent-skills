# GitHub commands

Commands for each step of SKILL.md, and their REST replacements when GraphQL is not available.

## When GraphQL is not available

In some environments, such as Claude Code on the web, the GitHub GraphQL API is rejected with `HTTP 403: GitHub GraphQL is not available ...`. Every `gh` command that uses GraphQL internally then fails: `gh issue view`, `gh pr list`, `gh repo view`, `gh pr create`, `gh pr comment`, `gh pr edit`, `gh pr view` and `gh pr checks`. Replace them with REST calls through `gh api` (`gh api repos/...`, `gh pr diff` and `gh run ...` still work).

| Purpose | Normal | Without GraphQL |
|---|---|---|
| Issue or PR | `gh api repos/{owner}/{repo}/issues/<number> --jq 'if .pull_request then "pr" else "issue" end'` (`repos/OWNER/REPO/...` for a target that names its repository, see below) | Same (REST) |
| The current branch's PR | `gh pr view --json number,url` | `gh api "repos/{owner}/{repo}/pulls?head=<head owner>:<branch>&state=open" --jq '.[] \| {number, html_url}'` |
| Read a PR (author, head, body) | `gh pr view <PR number> --json author,headRepository,headRefName,body,closingIssuesReferences,comments` | `gh api repos/{owner}/{repo}/pulls/<PR number> --jq '{user: .user.login, head: .head.repo.full_name, ref: .head.ref, base: .base.repo.full_name, base_ref: .base.ref, body}'` and the comments as in "Read an issue" (the issue comments endpoint also serves PRs); find closed issues in the body (`Closes`, `Fixes`, `Resolves`) |
| Current account | `gh api user --jq .login` | Same (REST) |
| Read an issue | `gh issue view <number> --comments` | `gh api repos/{owner}/{repo}/issues/<number>` and `gh api --paginate "repos/{owner}/{repo}/issues/<number>/comments?per_page=100"` |
| Recent PRs | `gh pr list --state all --limit 10` | `gh api "repos/{owner}/{repo}/pulls?state=all&per_page=10" --jq '.[] \| {number, title}'` |
| Default branch | `gh repo view --json defaultBranchRef` | `gh api repos/{owner}/{repo} --jq .default_branch` |
| Create a PR | `gh pr create ...` | `gh api repos/{owner}/{repo}/pulls -X POST -f title="<title>" -f head=<branch> -f base=<base branch> -F body=@<body file> --jq .html_url` |
| Comment on a PR | `gh pr comment <PR number> --body "..."` | `gh api repos/{owner}/{repo}/issues/<PR number>/comments -X POST -f body="..."` |
| Get the PR title and body | `gh pr view <PR number> --json title,body` | `gh api repos/{owner}/{repo}/pulls/<PR number> --jq '{title, body}'` |
| Update the PR title and body | `gh pr edit <PR number> --title "<title>" --body-file <body file>` | `gh api repos/{owner}/{repo}/pulls/<PR number> -X PATCH -f title="<title>" -F body=@<body file>` |
| Monitor the PR | `scripts/pr_status.sh` | Works as is (on a GraphQL 403 it switches to REST and the CCR route for review threads) |

- `gh api` replaces `{owner}/{repo}` with the repository of the current directory.
- **When the target names its repository** (`OWNER/REPO#<n>` or a URL), use that repository in every command about the target for this run, whether it is an issue or a PR, starting with the lookup that tells which it is, instead of the placeholder or the default: `repos/OWNER/REPO/...` for `gh api`, `-R OWNER/REPO` for other `gh` commands, and `OWNER/REPO` as the second argument of `scripts/pr_status.sh`. Numbers repeat across repositories, so the placeholder can reach another issue or PR with the same number, enter the wrong workflow or post replies there. Use the current directory's repository only for a bare number or no target. Change files only in a checkout of that repository (`git remote -v`); otherwise ask in chat.
- **An issue the PR closes** belongs to the repository its reference names (`Closes OWNER/OTHER#<n>`, or `closingIssuesReferences[].url`), else to the PR's repository. Read it and its comments there, not with the PR's repository, which may hold an unrelated issue with the same number.
- `-F body=@<file>` uses the file's contents as the body.
- On the REST path of `scripts/pr_status.sh`, `reviewDecision` and `threads[].id` (the GraphQL thread ID) are `null`. This does not affect `verdict`.
- With an old `gh` whose `gh pr checks` has no `--json` (such as 2.46), `scripts/pr_status.sh` gets only the CI state through REST.

## Before implementing

```bash
gh api repos/{owner}/{repo}/issues/<number> --jq 'if .pull_request then "pr" else "issue" end'   # is the target an issue or a PR?
gh issue view <number> --comments                # read the issue and its comments
gh pr view <PR number> --comments                # for a PR target: its body and comments
git log --oneline -20                            # language and style of existing commits
gh pr list --state all --limit 10                # language and style of existing PRs
gh repo view --json defaultBranchRef             # base branch
```

## Creating the PR

```bash
git push -u origin <branch>
printf '\n%s\n' "$(cat <signature file>)" >> <body file>   # the PR body ends with the signature, without a marker
gh pr create --base <base branch> --title "<title>" --body-file <body file>
```

## Monitoring

```bash
scripts/pr_status.sh <PR number> [owner/repo]    # CI, reviews, threads and verdict as JSON
gh run view <run-id> --log-failed                # logs of the failed jobs
gh run rerun <run-id> --failed                   # re-run the failed jobs once (suspected flaky)
# Resolve a conflict by merging the base branch of the PR's base repository, never by rebasing.
# <base remote> is the remote whose URL is that repository (git remote -v); origin may be a fork.
gh api repos/{owner}/{repo}/pulls/<PR number> --jq '{base: .base.repo.full_name, base_ref: .base.ref}'
git fetch <base remote> <base ref>
git merge FETCH_HEAD
```

## Signature

Generate the signature once per run into a file outside the repository, and read that file for every comment and for the PR body ("Signature" in `review-protocol.md`). Do not keep it in a shell variable: variables do not survive between tool calls, and an empty one posts an unsigned comment without any error. `<agent>` is the agent you are running in (`claude-code`, `codex` or `chatgpt`); pass `--model` and `--effort` only with the values your own instructions state, and leave out the rest; never guess a value:

```bash
scripts/signature.sh --agent <agent> --model <model ID> --effort <effort> > <signature file>
```

## Replying to review comments

End every comment with the signature and then the marker `<!-- issue-to-pr -->` (see `review-protocol.md`). Write the text with a quoted heredoc, so backticks and `$` in it stay as they are, append the signature and the marker, and post the file:

```bash
cat > <body file> <<'BODY'
...
BODY
printf '\n%s\n<!-- issue-to-pr -->\n' "$(cat <signature file>)" >> <body file>

# Reply to an inline review comment (thread)
gh api repos/{owner}/{repo}/pulls/<PR number>/comments/<comment_id>/replies -F body=@<body file>

# Comment on the whole PR, or reply to a review body
gh pr comment <PR number> --body-file <body file>
```

## Updating the PR title and body

Fetch the current title and body from the PR, not from the local file used at creation, because it may be stale or someone may have edited it on GitHub.

```bash
gh pr view <PR number> --json title,body
gh pr edit <PR number> --title "<title>" --body-file <body file>
```
