# GitHub commands

Commands used by SKILL.md, and their REST replacements when GraphQL is not available.

## When GraphQL is not available

In some environments, such as Claude Code on the web, the GitHub GraphQL API is rejected with `HTTP 403: GitHub GraphQL is not available ...`. Every `gh` command that uses GraphQL internally then fails: `gh issue create`, `gh issue list`, `gh pr list` and `gh label list`. Replace them with REST calls through `gh api` (`gh api repos/...` still works).

| Purpose | Normal | Without GraphQL |
|---|---|---|
| List labels | `gh label list` | `gh api --paginate "repos/<owner>/<repo>/labels?per_page=100" --jq '.[].name'` |
| Recent issues | `gh issue list --state all --limit 10` | `gh api "repos/<owner>/<repo>/issues?state=all&per_page=20" --jq '.[] \| select(.pull_request == null) \| .title'` (the endpoint also returns PRs, so filter them out) |
| Recent PRs | `gh pr list --state all --limit 10` | `gh api "repos/<owner>/<repo>/pulls?state=all&per_page=10" --jq '.[].title'` |
| Create an issue | `gh issue create ...` | See "Creating the issue" below |

## Finding issue templates

```bash
# When there is no local clone
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE --jq '.[].name'
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/<file> --jq .content | base64 -d
```

## Creating the issue

Write the body to a temporary file and pass it with `--body-file`, so shell quoting cannot break the body.

```bash
gh issue create --repo <owner>/<repo> \
  --title "<title>" --body-file /tmp/issue-body.md \
  --label "<label>" --milestone "<milestone>"
```

Without GraphQL:

```bash
gh api repos/<owner>/<repo>/issues -X POST \
  -f title="<title>" -F body=@/tmp/issue-body.md \
  -f 'labels[]=<label>' -F milestone=<milestone number> \
  --jq '{number, id, url: .html_url}'
```

- `-F body=@<file>` uses the file's contents as the body.
- The milestone is given by number, not name (`gh api repos/<owner>/<repo>/milestones --jq '.[] | {number, title}'`).
- The `id` in the output is what `sub_issue_id` needs when linking a sub-issue.

## Linking a sub-issue

```bash
gh api repos/<owner>/<repo>/issues/<parent number>/sub_issues -X POST -F sub_issue_id=<child id>
```

`sub_issue_id` is the child issue's `id`, not its number (`gh api repos/<owner>/<repo>/issues/<child number> --jq .id`).
