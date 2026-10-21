# GitHub commands

Use the `gh` CLI. Replace `OWNER`, `REPO`, `NUMBER` and `PR_URL` with the target PR's values.

## When GraphQL is not available (Claude Code on the web, etc.)

In some environments `gh api graphql` and every `gh` command that uses GraphQL internally fail with `HTTP 403: GitHub GraphQL is not available ...`: `gh pr view`, `gh pr checks`, `gh pr list`, `gh pr review`, `gh pr comment`, `gh pr merge`, `gh issue view` and `gh repo view`. Then use the REST (`gh api repos/...`) commands under "Without GraphQL" in each section. `gh pr diff` and `gh api repos/...` still work.

| Purpose | Normal | Without GraphQL |
|---|---|---|
| PR information | `gh pr view` | `gh api repos/OWNER/REPO/pulls/NUMBER` |
| CI state | `gh pr checks` | `gh api repos/OWNER/REPO/commits/HEAD_SHA/check-runs` and `.../commits/HEAD_SHA/status` |
| Recent PRs | `gh pr list` | `gh api "repos/OWNER/REPO/pulls?state=all&per_page=5"` |
| List threads | GraphQL `reviewThreads` | `gh api repos/OWNER/REPO/pulls/NUMBER/ccr/review_threads` (CCR route) |
| Reply to a thread | GraphQL `addPullRequestReviewThreadReply` | `gh api repos/OWNER/REPO/pulls/NUMBER/comments/ROOT_COMMENT_ID/replies -X POST -f body=...` |
| Resolve | GraphQL `resolveReviewThread` | `gh api repos/OWNER/REPO/pulls/NUMBER/ccr/comments/ROOT_COMMENT_ID/resolve -X POST` (CCR route) |
| Comment on the PR | `gh pr comment` | `gh api repos/OWNER/REPO/issues/NUMBER/comments -X POST -f body=...` |
| Approve | `gh pr review --approve` | `gh api repos/OWNER/REPO/pulls/NUMBER/reviews -X POST -f event=APPROVE -f body=...` |
| Read an issue | `gh issue view` | `gh api repos/OWNER/REPO/issues/ISSUE_NUMBER` |
| PRs for an issue | GraphQL `closedByPullRequestsReferences` | `cross-referenced` events in `gh api repos/OWNER/REPO/issues/ISSUE_NUMBER/timeline` |
| Merge | `gh pr merge` | `gh api repos/OWNER/REPO/pulls/NUMBER/merge -X PUT -f merge_method=... -f sha=HEAD_SHA` |

- Review threads cannot be listed or resolved through REST, so use the CCR route (`repos/OWNER/REPO/pulls/NUMBER/ccr/...`) provided by the cloud proxy. It works only in cloud environments; where GraphQL works, keep using GraphQL.
- Paths outside the repository, such as `search/issues`, may be unavailable. Use endpoints under `repos/OWNER/REPO/...` instead.

## Contents
1. Getting PR information
2. Posting a review
3. Listing, replying to and resolving threads
4. Reading an issue and finding the PR for an issue
5. Choosing the merge method
6. Merging

## 1. Getting PR information

```bash
gh pr view PR_URL --json number,title,body,author,baseRefName,headRefName,headRefOid,isDraft,state,mergeable,mergeStateStatus,reviewDecision,url
gh pr diff PR_URL
gh pr checks PR_URL          # CI state
```

The diff since the last checked SHA (when there are new commits):

```bash
gh api repos/OWNER/REPO/compare/OLD_SHA...NEW_SHA --jq '.files[] | {filename, status, patch}'
```

If OLD_SHA is gone from the history (force push, etc.), check the unresolved findings against the whole PR diff.

Without GraphQL:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER \
  --jq '{number, title, body, author: .user.login, base: .base.ref, head: .head.ref, headSha: .head.sha, draft, state, merged, mergeable, mergeable_state, url: .html_url}'
# CI state (HEAD_SHA is headSha above). Look at both check runs and commit statuses
gh api "repos/OWNER/REPO/commits/HEAD_SHA/check-runs?per_page=100" --jq '.check_runs[] | {name, status, conclusion, details_url}'
gh api "repos/OWNER/REPO/commits/HEAD_SHA/status" --jq '.statuses[] | {context, state, target_url}'
```

- `state` is `open` / `closed`. A merged PR has `merged` set to `true`.
- `mergeable` is `true` (mergeable) / `false` (conflict) / `null` (GitHub is still computing; wait a little and fetch again).
- REST has no equivalent of `reviewDecision`. Check the review state with `gh api repos/OWNER/REPO/pulls/NUMBER/reviews`.
- A check run is running until its `status` is `completed`. Treat a `conclusion` other than `success`, `skipped` or `neutral` as a failure.

Recent PRs and review comments, to decide the comment language:

```bash
gh pr list --repo OWNER/REPO --state all --limit 5 --json number,title,body
# Without GraphQL
gh api "repos/OWNER/REPO/pulls?state=all&per_page=5" --jq '.[] | {number, title, body}'
```

## 2. Posting a review

Post the inline comments and the summary in one API call. Writing the JSON to a file first avoids escaping problems with newlines and backticks.

```bash
cat > review.json <<'EOF'
{
  "commit_id": "HEAD_SHA",
  "event": "COMMENT",
  "body": "## Review result\n...\n\n<!-- pr-review -->",
  "comments": [
    {
      "path": "src/foo.py",
      "line": 42,
      "side": "RIGHT",
      "body": "**[P1 (High)] ...**\n\n...\n\n<!-- pr-review -->"
    }
  ]
}
EOF
gh api repos/OWNER/REPO/pulls/NUMBER/reviews -X POST --input review.json
```

- `line` is the line number in the changed file and must be a line in the diff. For a range, also set `start_line` and `start_side`.
- Write a `suggestion` block in the comment body like this (the given lines are what it replaces):
  ````
  ```suggestion
  fixed code
  ```
  ````
- A comment cannot be attached to a line outside the diff; attach it to the most related changed line instead.

Post a file-level comment (a finding not tied to a line) separately from the review:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments -X POST \
  -f commit_id=HEAD_SHA -f path=src/foo.py -f subject_type=file \
  -f body='**[P2 (Medium)] ...**

<!-- pr-review -->'
```

### Approve (only when the author is a different account)

Post it when the merge conditions are met. It fails on the author's own account.

```bash
gh pr review PR_URL --approve --body 'Confirmed that all merge conditions are met (HEAD_SHA).

<!-- pr-review -->'
```

The author's login: `gh pr view PR_URL --json author --jq .author.login`. Your own login: `gh api user --jq .login`.

Without GraphQL:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/reviews -X POST -f event=APPROVE \
  -f body='Confirmed that all merge conditions are met (HEAD_SHA).

<!-- pr-review -->'
gh api repos/OWNER/REPO/pulls/NUMBER --jq .user.login   # the author's login
```

## 3. Listing, replying to and resolving threads

List the threads (resolved or not, and their comments):

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first:50) {
            nodes { databaseId body author { login } createdAt url }
          }
        }
      }
    }
  }
}' -F owner=OWNER -F repo=REPO -F number=NUMBER
```

- This skill's threads are those whose first comment contains `<!-- pr-review -->`.
- Whether the author replied is decided by whether the last comment lacks the marker.

Reply to a thread:

```bash
gh api graphql -f query='
mutation($id:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id, body:$body}) { comment { url } }
}' -F id=THREAD_ID -f body='Confirmed (fixed in abc1234).

<!-- pr-review -->'
```

Resolve:

```bash
gh api graphql -f query='
mutation($id:ID!) { resolveReviewThread(input:{threadId:$id}) { thread { isResolved } } }' -F id=THREAD_ID
```

Comment on the whole PR (e.g. the record before merging):

```bash
gh pr comment PR_URL --body '...

<!-- pr-review -->'
```

### Without GraphQL

List the threads through the CCR route. It returns only each thread's state and comment IDs, so look up bodies and authors by ID in the review comment list:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/ccr/review_threads
# [{"resolved":false,"outdated":false,"path":"src/foo.py","line":42,"comment_ids":[123,456]}, ...]
gh api --paginate "repos/OWNER/REPO/pulls/NUMBER/comments?per_page=100" \
  --jq '.[] | {id, user: .user.login, body, created_at, in_reply_to_id, html_url}'
```

- `comment_ids` are in posting order, and the first is the thread's first comment (the root comment). The thread ID (`THREAD_ID`) is not available, so reply and resolve by the root comment's ID.
- Whether a thread is this skill's, and whether it has a reply, is decided by the marker, as with GraphQL.

Reply to a thread (REST; also works where GraphQL works):

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/comments/ROOT_COMMENT_ID/replies -X POST \
  -f body='Confirmed (fixed in abc1234).

<!-- pr-review -->'
```

Resolve (to undo, replace `resolve` with `unresolve`):

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/ccr/comments/ROOT_COMMENT_ID/resolve -X POST
# {"comment_ids":[123,456],"resolved":true}
```

Comment on the whole PR:

```bash
gh api repos/OWNER/REPO/issues/NUMBER/comments -X POST -f body='...

<!-- pr-review -->'
```

## 4. Reading an issue

```bash
gh issue view ISSUE_NUMBER --repo OWNER/REPO --json number,title,body,state,url
# Without GraphQL
gh api repos/OWNER/REPO/issues/ISSUE_NUMBER --jq '{number, title, body, state, url: .html_url}'
gh api --paginate "repos/OWNER/REPO/issues/ISSUE_NUMBER/comments?per_page=100" --jq '.[] | {user: .user.login, body, created_at}'
```

### Finding the PR for an issue

Get both the PRs that will close the issue (by a keyword such as `Closes #123`, or linked on the PR page) and the PRs that reference the issue:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    issue(number:$number) {
      state
      closedByPullRequestsReferences(first:10, includeClosedPrs:true) {
        nodes { number url state isDraft headRefName createdAt }
      }
      timelineItems(itemTypes:[CROSS_REFERENCED_EVENT], last:20) {
        nodes {
          ... on CrossReferencedEvent {
            source { ... on PullRequest { number url state isDraft headRefName createdAt } }
          }
        }
      }
    }
  }
}' -F owner=OWNER -F repo=REPO -F number=ISSUE_NUMBER
```

- Prefer the PRs in `closedByPullRequestsReferences`; they are meant to resolve the issue.
- A PR in `timelineItems` may only mention the issue, so check its description and title to see whether it addresses the issue.
- As a fallback when neither has one, search for PRs that mention the issue in their description:
  ```bash
  gh pr list --repo OWNER/REPO --state open --search "ISSUE_NUMBER in:body" --json number,title,url,isDraft
  ```

#### Without GraphQL

REST has no equivalent of `closedByPullRequestsReferences`. Get the PRs that mentioned the issue (`cross-referenced` events) from the issue's timeline:

```bash
gh api --paginate "repos/OWNER/REPO/issues/ISSUE_NUMBER/timeline?per_page=100" --jq '
  .[] | select(.event == "cross-referenced" and .source.issue.pull_request != null
               and .source.issue.repository.full_name == "OWNER/REPO")
  | .source.issue | {number, url: .html_url, state, draft, merged_at: .pull_request.merged_at, body}'
```

- Prefer, as PRs that will close the issue, those whose description has a keyword such as `Closes #ISSUE_NUMBER` (close, fix, resolve and their inflections). A PR linked only manually on the PR page cannot be told apart this way.
- The others may only mention the issue, so check their description and title.
- `search/issues` may be unavailable, so as a fallback when neither has one, scan the descriptions of open PRs directly:
  ```bash
  gh api --paginate "repos/OWNER/REPO/pulls?state=open&per_page=100" \
    --jq '.[] | select(.body // "" | test("#ISSUE_NUMBER\\b")) | {number, title, url: .html_url, draft}'
  ```

## 5. Choosing the merge method

Allowed methods and the automatic branch deletion setting:

```bash
gh api repos/OWNER/REPO --jq '{allow_merge_commit, allow_squash_merge, allow_rebase_merge, delete_branch_on_merge}'
```

Infer the method of existing merged PRs (about the last 10):

```bash
gh pr list --repo OWNER/REPO --state merged --limit 10 --json number,mergeCommit,commits \
  --jq '.[] | {number, sha: .mergeCommit.oid, commits: (.commits | length)}'
gh api repos/OWNER/REPO/commits/SHA --jq '{parents: (.parents | length), message: .commit.message}'
```

- Two parents → merge
- One parent, and the message starts with the PR title and `(#number)` → squash
- One parent, otherwise (the PR's commits appear as they are) → rebase

Use the majority method. Never choose a method that is not allowed.

Without GraphQL, use this instead of `gh pr list` (PRs with `merged_at` are merged):

```bash
gh api "repos/OWNER/REPO/pulls?state=closed&per_page=30" \
  --jq '.[] | select(.merged_at != null) | {number, title, sha: .merge_commit_sha}' | head -10
gh api repos/OWNER/REPO/pulls/NUMBER --jq .commits   # number of commits in the PR
```

## 6. Merging

```bash
gh pr merge PR_URL --squash --delete-branch --match-head-commit HEAD_SHA
# one of --merge / --squash / --rebase
```

- With `--match-head-commit`, the merge fails if the head changed since the SHA you checked, so unchecked commits are never merged.
- For squash and merge, do not pass `--subject` or `--body` (the repository's default message is used, usually the PR title and description).
- If the repository deletes branches automatically, `--delete-branch` is unnecessary but harmless.

Without GraphQL:

```bash
gh api repos/OWNER/REPO/pulls/NUMBER/merge -X PUT -f merge_method=squash -f sha=HEAD_SHA
# merge_method is one of merge / squash / rebase
# If automatic deletion is off, delete the branch after merging
gh api repos/OWNER/REPO/git/refs/heads/HEAD_BRANCH -X DELETE
```

- With `sha`, the merge fails if the head changed since the SHA you checked (same as `--match-head-commit`).
- Do not set `commit_title` or `commit_message` (leave the repository's default message).
