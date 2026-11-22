# GitHub reads and writes

Resolve a bare `#N` against the current repository and host (`gh repo view --json url --jq .url` or inspect `git remote -v` if GraphQL is unavailable). For `OWNER/REPO#N` use the named repository on `github.com`. For a GitHub issue URL use the host and repository in the URL. In the commands below, `host`, `repo`, and `log` are that host, repository, and issue number.

## Read the log and investigate

`scripts/read-log.py "$repo" "$log" --hostname "$host"` needs Python 3 and `gh`. It uses only REST and reads every comments page.

```bash
gh api "repos/$repo/issues/$log" --hostname "$host"
gh api --paginate "repos/$repo/issues/$log/comments?per_page=100" --hostname "$host"
```

The helper returns one JSON object with `repository`, `number`, `url`, and ordered `rows`. Each row has `id`, `summary`, `status`, `comment_url`, and `item`. An item has `pr`, `issue` (the issue from its PR heading), `sha`, `location`, `observation`, `not_raised_because`, `related` and `source`. The helper follows the link in each row. When it cannot recover the item from that log comment, it returns `item: null` and `item_error` for that row. Usage, API and log structure errors exit with status 2 and no JSON.

- Read a referenced issue and its discussion with `gh issue view N -R "$host/$repo" --comments`. With REST use `gh api "repos/$repo/issues/N" --hostname "$host"` and `gh api --paginate "repos/$repo/issues/N/comments?per_page=100" --hostname "$host"`. Inspect `pull_request` to exclude PRs when looking for issues.
- Use the paginated REST search below for open and closed issues. Inspect the full records of matches and narrow queries that hit GitHub's search result limit.
- Read a file from a verified checkout with `git show "$sha:$path"`. Without the Git object, resolve the SHA with `gh api "repos/$repo/commits/$sha" --hostname "$host" --jq .sha` and fetch the file at the resulting `full_sha`. Use a URL-encoded path in the Contents API.

```bash
gh api --paginate -X GET search/issues --hostname "$host" -f q="repo:$repo is:issue $terms" -F per_page=100
gh api -H 'Accept: application/vnd.github.raw+json' "repos/$repo/contents/$path?ref=$full_sha" --hostname "$host"
```

If search is unavailable or its results are incomplete, use the paginated repository issue listing under “Find earlier posts and recover retries”. Match the titles and bodies locally using the item's symptom, affected paths, or feature names, and inspect relevant matches in both states. If neither route gives enough information to check an item for duplicate or completed work, recommend Keep open and explain what could not be checked.

To find issue templates without a checkout, list `gh api "repos/$repo/contents/.github/ISSUE_TEMPLATE" --hostname "$host" --jq '.[].name'` and fetch each candidate with the Contents API and the raw media type above. Check the other paths and the owner's shared repository listed in the formats reference. A 404 means the path is absent. For existing labels use `gh label list -R "$host/$repo"`, or `gh api --paginate "repos/$repo/labels?per_page=100" --hostname "$host" --jq '.[].name'`.

## Find earlier posts and recover retries

Search is useful for finding related work. For retry markers use the paginated REST resources below because search can lag behind a successful post. These reads cover both open and closed issues and comments, including when a prior plan chose a different target.

```bash
gh api --paginate "repos/$repo/issues?state=all&per_page=100" --hostname "$host" \
  --jq '.[] | select(.pull_request == null) | {number, state, title, body, html_url}'
gh api --paginate "repos/$repo/issues/comments?per_page=100" --hostname "$host" \
  --jq '.[] | {issue_url, html_url, body}'
```

Look for a standalone line anywhere in the body that exactly matches the marker format for this log (repository names are case-insensitive). Ignore markers and backlinks inside code blocks or quoted examples. Require a backlink for each marked item that pairs its log comment URL with its item ID. Text after the marker, such as an appended footer, leaves the match valid. Compare individual item IDs, since groups may differ on retry. Check that any matched comment is on an issue in the log repository and host by reading its `issue_url` and ruling out PRs. A marked issue body supplies `issue #N`, and a marked fold comment supplies `in #N`. Include its URL in the plan. If multiple posts claim one item, report the conflict and leave its row open pending clarification.

Read markers while planning and refresh the check before executing the approved plan or retrying a post. If a marker already covers an item, skip posting it and use the existing result when it matches the approved plan. If only some members of a planned group are covered or the recovered outcome differs from the plan, present the updated plan for approval before posting anything for that group. On a failed or uncertain POST, check the markers before considering any retry. If the lookup fails, stop and report the uncertainty instead of posting again.

## Publish approved issues and comments

Verify that each fold target is still an open issue in the log repository. Once a plan is approved, write its Markdown bodies to temporary files. Pass any approved metadata and use the returned issue number and URLs when updating the log and reporting.

```bash
gh issue create -R "$host/$repo" --title "$title" --body-file "$issue_file"
gh issue comment "$target" -R "$host/$repo" --body-file "$comment_file"
```

With REST (works when GraphQL returns HTTP 403):

```bash
gh api "repos/$repo/issues" --hostname "$host" -X POST -f title="$title" -F body=@"$issue_file" \
  --jq '{number, html_url}'
gh api "repos/$repo/issues/$target/comments" --hostname "$host" -X POST -F body=@"$comment_file" \
  --jq '{html_url}'
```

Append the approved metadata to issue creation as needed. For REST use `-f 'labels[]=LABEL'`, `-f 'assignees[]=LOGIN'`, and `-F milestone=N`, with the milestone number from `gh api --paginate "repos/$repo/milestones?state=all&per_page=100" --hostname "$host"`. For `gh issue create` use `--label`, `--assignee` and `--milestone`.

## Record the approved statuses

After posting or recovering the approved work, get a fresh copy of the log, prepare the body, and PATCH it immediately. Select rows by their item IDs and log comment links in the Item / Summary / Status table. Compare them with the approved plan and preserve rows that are missing, no longer open or otherwise changed. Write no issue or fold status without a verified issue or comment. Keep open requires no write.

```bash
gh api "repos/$repo/issues/$log" --hostname "$host" > "$fresh_issue"
# Read .body from the JSON and save the edited Markdown to "$updated_body".
gh api "repos/$repo/issues/$log" --hostname "$host" -X PATCH -F body=@"$updated_body" --jq .html_url
```

Verify the fresh issue is the marked log. Change only the Status cell text of the selected rows. Preserve the cell padding, all other text and the final newline as received. Check the diff against the freshly fetched body before patching. Skip the patch when there are no changes. If time passes or a concurrent edit is reported before the patch, start from a new read. GitHub accepts the whole body here, so the fresh read reduces the window for overwriting concurrent edits.

Check the resulting statuses and report errors. If the patch fails, leave the approved posts in place. Their markers let a later run propose recording the missing statuses without repeating those posts.
