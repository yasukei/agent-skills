# Handoffs

Read before writing a prompt or message to the implementer or reviewer. Start each one with the skill invocation, then add only what the skill cannot know. Do not restate the skill's own rules: duplicated rules drift apart. Replace the placeholders, write the text in the user's language (see "Rules" in SKILL.md), and keep every handoff in plain text.

Every handoff ends with these lines:

```text
Do not use --watch. Stop when this step is done.
If something unexpected happens (you cannot follow the skill's procedure, the issue or comments are ambiguous or contradictory, or the environment fails), do not work around it silently: stop or ask, and state it in your final report.
```

## Implementer: first run

```text
$agent-skills:issue-to-pr <OWNER/REPO>#<issue> --worktree

A separate reviewer will review the PR. Review fixes will follow later in this same session.
Final report: PR number and URL, worktree path, branch, checks run and their results, CI state.
```

## Implementer: review fixes

```text
$agent-skills:issue-to-pr Handle the review comments on PR <OWNER/REPO>#<PR> --worktree. Use the same worktree as before: <path>.

Review: <review URL>
- <priority>: <file>:<line>, <one-line summary>: <comment URL>

The reviewer resolves threads after re-checking.
Final report: how each finding was handled (fix commit, or reason for declining), checks run and their results, CI state, the URLs of the replies you posted.
```

## Implementer: existing PR

Use this for a PR from an earlier session when the earlier Codex thread cannot be resumed. Give no worktree path: `issue-to-pr` finds or creates one.

```text
$agent-skills:issue-to-pr Handle the unresolved review comments and failing CI on PR <OWNER/REPO>#<PR> --worktree.

The reviewer resolves threads after re-checking.
Final report: how each finding was handled (fix commit, or reason for declining), worktree path, branch, checks run and their results, CI state, the URLs of the replies you posted.
```

## Implementer: CI failure

```text
$agent-skills:issue-to-pr Fix the failing CI on PR <OWNER/REPO>#<PR> --worktree. Use the same worktree as before: <path>.

Failing checks:
- <check name>: <URL>

Final report: the cause, the fix commit (or why it is unrelated to this PR), checks run and their results.
```

## Reviewer: first review

Start it with the Agent tool, at `effort: "high"`, in the target repository's checkout.

```text
Run the skill agent-skills:pr-review with arguments `<OWNER/REPO>#<PR> --worktree`.

You run at effort high; use that value in your signature.
The PR implements issue #<issue>. It was written by <implementer agent> through issue-to-pr. Fix requests and your re-check will follow later through this same conversation, so remember your findings.
Final report: verdict (ready to merge, or changes needed), findings (priority, file and line, content), what you posted with URLs, worktree path, checks run and their results.
```

## Reviewer: re-check

Send it with SendMessage to the same reviewer.

```text
The implementer pushed fixes to PR <OWNER/REPO>#<PR>. Re-check them as a continuation of your review, following agent-skills:pr-review with --worktree.

Implementer's report:
- <finding>: <fixed in SHA / declined because …>: <reply URL>
CI: <state>

Final report: each finding (resolved, or not and why), threads resolved, new findings, what you posted with URLs, checks run and their results, final merge verdict.
```

## Reviewer: merge

Send this only when the user gave `--merge`, or approved this merge later in the conversation.

```text
The user approved merging PR <OWNER/REPO>#<PR>. Merge it following agent-skills:pr-review with --merge.
Before merging, re-check the merge conditions. If anything changed since your last check (head SHA, CI, unresolved threads, merge state), do not merge; report instead.

Final report: merge result (method, merge commit, PR and issue state), the pre-merge check, anything cleaned up or left in place.
```

## Answering a question

Resume the same agent. State whose decision the answer is:

- The user's answer: "The user decided: <answer>."
- Under `--delegate`: "Under --delegate, the orchestrator chose your recommendation <answer>. The user has not seen this decision; record it in the PR (e.g. Review focus or the thread)."
