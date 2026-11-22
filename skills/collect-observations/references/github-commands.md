# GitHub commands

Read when you resolve the targets to PRs, look for existing logs, create the log, post a log comment or update the log body. Every command here except the first one under "Merged PRs of an issue" uses REST (`gh api repos/...`), which works where GitHub GraphQL returns HTTP 403 (e.g. Claude Code on the web); that one has a REST fallback. `gh issue create`, `gh issue list` and `gh issue edit` use GraphQL; do not use them.

`repo` is `OWNER/REPO`. The issues endpoints also return PRs; `.pull_request != null` marks a PR. GitHub accepts any letter case in `OWNER/REPO` but returns its own casing in `repository_url` and `nameWithOwner`, so compare repository names in lowercase (`ascii_downcase` in jq).

## Resolving the targets

### Is a number a PR or an issue?

```bash
gh api "repos/${repo:?}/issues/${n:?}" --jq '{number, title, state, is_pr: (.pull_request != null)}'
```

### Merged PRs of an issue

Use GitHub's own closing relationship first. It covers both closing keywords in a PR body and a PR linked in the issue's Development sidebar, which has no keyword. Keep the merged PRs in the same repository; a PR in another repository has a number that means nothing here:

```bash
gh api graphql -f owner="${repo%%/*}" -f name="${repo#*/}" -F n="${issue:?}" -f query='
  query($owner: String!, $name: String!, $n: Int!) {
    repository(owner: $owner, name: $name) { issue(number: $n) {
      closedByPullRequestsReferences(first: 50, includeClosedPrs: true) {
        nodes { number merged repository { nameWithOwner } } } } } }' |
  jq --arg repo "${repo:?}" '[.data.repository.issue.closedByPullRequestsReferences.nodes[]
    | select(.merged and (.repository.nameWithOwner | ascii_downcase) == ($repo | ascii_downcase)) | .number]'
```

Where GraphQL returns HTTP 403, fall back to the timeline. Candidates are PRs in the same repository that the issue's timeline lists as cross-references:

```bash
gh api --paginate "repos/${repo:?}/issues/${issue:?}/timeline?per_page=100" | jq -s --arg repo "${repo:?}" '
  [.[][] | select(.event == "cross-referenced") | .source.issue
   | select(.pull_request != null
            and (.repository_url | ascii_downcase) == ("https://api.github.com/repos/" + $repo | ascii_downcase))
   | .number] | unique'
```

A mention does not make a PR the issue's implementation. In the fallback, keep a candidate only if it is merged and its body closes the issue (`Closes #<issue>`, `Fixes`, `Resolves`, also as `OWNER/REPO#<issue>`), as `issue-to-pr` writes it:

```bash
gh api "repos/${repo:?}/pulls/${pr:?}" | jq --arg repo "${repo:?}" --arg issue "${issue:?}" '
  {number, merged,
   closes_issue: (.body // "" | test("(?i)\\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?\\s+(" + $repo + ")?#" + $issue + "\\b"))}'
```

The fallback cannot see a PR linked only in the Development sidebar. An issue with no PR found goes into the plan as "no merged PR found", with the merged candidates that only mention it, so the user can add one by number. Say in the plan that the fallback was used.

### Sub-issues

```bash
gh api --paginate "repos/${repo:?}/issues/${issue:?}/sub_issues?per_page=100" \
  --jq '.[] | {number, title, state, repo: (.repository_url | sub("^https://api.github.com/repos/"; ""))}'
```

A sub-issue can be in another repository, and its number means nothing in `repo`. Keep only sub-issues whose `repo` equals `repo` (in lowercase), and list the others in the plan as skipped: they need a log in their own repository. Repeat for each kept sub-issue, so sub-issues of sub-issues are included. Keep a set of the numbers you visited, so a loop cannot repeat.

### Milestone

Find the milestone's number from its title, then list its issues and PRs:

```bash
gh api --paginate "repos/${repo:?}/milestones?state=all&per_page=100" --jq '.[] | {number, title, state}'
gh api --paginate "repos/${repo:?}/issues?milestone=${milestone:?}&state=all&per_page=100" \
  --jq '.[] | {number, title, is_pr: (.pull_request != null)}'
```

Take the PRs as they are, and resolve each issue to its merged PRs as above. Remove duplicates.

## Scanning

```bash
"${skill_dir:?}/scripts/scan.sh" "${repo:?}" [--log "${log:?}"] PR...
```

`skill_dir` is this skill's absolute directory. The script prints one JSON line per PR; the fields and statuses are in its header comment and in SKILL.md. Exit status 2 is a usage or GitHub API error: report it, and do not read it as "nothing collected".

## Existing logs

List marked log issues in both states. Match the scope using the milestone, parent or scope named in the log. Without `--log`, offer matching open logs as append targets. Name matching closed logs in the plan as predecessors of a new log.

```bash
gh api --paginate "repos/${repo:?}/issues?state=all&per_page=100" | jq -s '
  [.[][] | select(.pull_request == null and (.body // "" | contains("<!-- collect-observations:log -->")))
   | {number, title, html_url, state, milestone: .milestone.number}]'
```

Read the body of a candidate if its title and milestone do not establish the scope. Read the explicit `--log` issue directly, since a log written by hand may lack the marker.

## Reading the log

```bash
gh api "repos/${repo:?}/issues/${log:?}" --jq '{number, title, state, body}'
gh api --paginate "repos/${repo:?}/issues/${log:?}/comments?per_page=100" --jq '.[] | {id, html_url, body}'
```

The observations comment of a PR is the `body` of the comment that `scan.sh` lists under `observations`:

```bash
gh api "repos/${repo:?}/issues/comments/${comment_id:?}" --jq .body
```

## Reopening a log

Repairs belong to the log that holds the copied comments. If a repair would write to a closed log, ask the user whether to reopen that log or leave the repair pending. Choosing a new log for new observations leaves the closed log and its repairs as they are, unless reopening it for repairs was also approved.

Before appending or repairing, check the destination's current state. If it closed since approval, ask before writing or reopening. Reopen only the issue and work approved in the plan:

```bash
gh api "repos/${repo:?}/issues/${log:?}" -X PATCH -f state=open --jq '{html_url, state}'
```

Verify the issue is open before posting comments or updating its body. If reopening fails or cannot be verified, report it and skip writes to that log.

## Labels, milestones and parent

```bash
gh api --paginate "repos/${repo:?}/labels?per_page=100" --jq '.[].name'
# A parent issue's id (not its number) is needed to add the log as a sub-issue
gh api "repos/${repo:?}/issues/${n:?}" --jq .id
```

## Creating the log

Write the body to `BODY_FILE` with a quoted heredoc, so backticks and `$` stay as they are. Use `-f` for strings and `-F` for numbers and files:

```bash
gh api "repos/${repo:?}/issues" -X POST -f title="TITLE" -F body=@BODY_FILE \
  -f 'labels[]=LABEL' -F milestone=MILESTONE_NUMBER --jq '{number, html_url, id}'
```

Drop `labels[]` or `milestone` when there is none. To link the log under a parent issue:

```bash
gh api "repos/${repo:?}/issues/${parent:?}/sub_issues" -X POST -F sub_issue_id=LOG_ID
```

If linking fails, `Part of #<parent>.` in the body is enough; mention it in the final report.

## Posting a log comment

Generate the signature once into `SIG_FILE`, a file outside the repository (e.g. from `mktemp`). Pass `--model` only with the model ID your own instructions state, and `--effort` only if they state one; never guess:

```bash
"${skill_dir:?}/scripts/signature.sh" --agent claude-code --model MODEL_ID > SIG_FILE
```

Use `--agent codex` or `--agent chatgpt` when you are that agent. Append a blank line, the signature and the source markers to the comment body, then post it:

```bash
{ echo; cat SIG_FILE; cat MARKERS_FILE; } >> COMMENT_FILE
gh api "repos/${repo:?}/issues/${log:?}/comments" -X POST -F body=@COMMENT_FILE --jq '{id, html_url}'
```

Read `SIG_FILE` in the post rather than a shell variable: variables do not survive between tool calls, and an empty one posts an unsigned comment without any error.

A post can succeed even when its response is lost. Before retrying a failed post, read the log's comments again and look for its source markers.

## Updating the log body

Read the body again right before you write it, so an edit someone made in the meantime is kept, then:

```bash
gh api "repos/${repo:?}/issues/${log:?}" -X PATCH -F body=@BODY_FILE --jq .html_url
```

An issue body and a comment can each hold at most 65,536 characters (`wc -m`).
