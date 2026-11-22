# Handoffs

Read before writing a prompt or message to the implementer or reviewer. Start each one with the skill invocation, then add only what the skill cannot know. Do not restate the skill's own rules: duplicated rules drift apart. Replace the placeholders (`<issue-to-pr>` and `<pr-review>` are the installed skill names, see "Installed skill names" below), write the text in English (see "Language" below), and keep every handoff in plain text.

The "Final report" parts of the implementer's first run and existing-PR run, and of the reviewer's first review and re-check, ask for observations with the fields in `observations.md`, so the final report needs no lookups afterwards. Keep them in step with that file.

Every handoff ends with these lines. Append them if the template does not already contain them:

```text
Do not use --watch. Stop when this step is done.
If the skill named above is not available, stop and say so instead of doing the work without it.
If something unexpected happens (you cannot follow the skill's procedure, the issue or comments are ambiguous or contradictory, or the environment fails), do not work around it silently: stop or ask, and state it in your final report.
```

## Installed skill names

`<issue-to-pr>` and `<pr-review>` are the names the skills are installed under: `agent-skills:<name>` from the plugin, plain `<name>` when installed as a standalone skill (`.claude/skills/<name>`, `.agents/skills/<name>`). For a Claude Code agent, use the name in your own skill list. For Codex, use `<name>` if the target checkout has `.agents/skills/<name>`, else `agent-skills:<name>`.

## Language

Write handoffs, follow-up messages and answers to agents in English, whatever language the user writes in. The templates are in English, and translating them can drift from the template or drop an item. Repository text is often English too, so an English handoff keeps the agent from reading in one language and writing in another.

Every template has this line. Replace `<language>` with the language the user writes to you in (e.g. Japanese):

```text
The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.
```

- The first sentence keeps the skills' fallback right. They write commits, PRs and comments in the repository's language, else in the user's, and to them the author of the handoff is the user. An English handoff alone would make that fallback English.
- The last sentence keeps the agent's reports and questions in English. The skills reply in chat in the user's language, which they would take from the first sentence.
- Toward the user, use the user's language: relay questions as "Asking the user" in `decisions.md` says, and write the final report in it.

## Implementer: first run

```text
$<issue-to-pr> <OWNER/REPO>#<issue> --worktree

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

A separate reviewer will review the PR. Review fixes will follow later in this same session.
Final report: PR number and URL, worktree path, branch, checks run and their results, CI state.
Also report each thing you noticed but left out of the PR: your head SHA, file:line (several allowed; a file alone if it concerns the whole file), what you noticed, why you left it out (e.g. outside the issue), and the related future issue or milestone (or none, or unknown).
```

## Implementer: review fixes

```text
$<issue-to-pr> Handle the review comments on PR <OWNER/REPO>#<PR> --worktree. Use the same worktree as before: <path>.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

Review: <review URL>
- <priority>: <file>:<line>, <one-line summary>: <comment URL>

The reviewer resolves threads after re-checking.
Final report: how each finding was handled (fix commit, or reason for declining), checks run and their results, CI state, the URLs of the replies you posted.
```

## Existing PR

If an issue already has an open PR (e.g. from an earlier session), continue from it instead of starting over:

- Start a new reviewer. It will ask before resolving threads of the earlier reviewer's session; that is a type A question for the user.
- For fixes, resume Codex with the `session` value from the `agent=codex` signature in the PR body, if `codex exec resume` accepts it. Otherwise, start a new implementer run with the PR as the target, using "Implementer: existing PR" below.

## Implementer: existing PR

Use this when the earlier Codex thread cannot be resumed and the new run has no context from that thread. Omit the worktree path so `issue-to-pr` can find or create the checkout for the PR.

```text
$<issue-to-pr> <OWNER/REPO>#<PR> --worktree

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

The reviewer resolves threads after re-checking.
Final report: how each finding was handled (fix commit, or reason for declining), worktree path, branch, checks run and their results, CI state, the URLs of the replies you posted.
Also report each thing you noticed but left out of the PR: your head SHA, file:line (several allowed; a file alone if it concerns the whole file), what you noticed, why you left it out (e.g. outside the issue), and the related future issue or milestone (or none, or unknown).
```

## Implementer: CI failure

```text
$<issue-to-pr> Fix the failing CI on PR <OWNER/REPO>#<PR> --worktree. Use the same worktree as before: <path>.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

Failing checks:
- <check name>: <URL>

Final report: the cause, the fix commit (or why it is unrelated to this PR), checks run and their results.
```

## Implementer: conflict

Resume the implementer in its existing worktree. If you have not recorded a worktree for an existing PR, follow "Existing PR" above, omit the sentence specifying the path, and ask for the path and branch in the final report. If review findings also need work, add the review URL, findings and reporting requirements from "Implementer: review fixes" before the closing lines. Include any failing check links reported for the same head.

```text
$<issue-to-pr> Resolve the conflict with the base branch on PR <OWNER/REPO>#<PR> --worktree. Use the same worktree as before: <path>.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

The reviewer will re-check the resolution after CI.
Final report: the resolution commit, the conflicting files, checks run and their results, and CI state.

Do not use --watch. Stop when this step is done.
If the skill named above is not available, stop and say so instead of doing the work without it.
If something unexpected happens (you cannot follow the skill's procedure, the issue or comments are ambiguous or contradictory, or the environment fails), do not work around it silently: stop or ask, and state it in your final report.
```

## Reviewer: first review

Start it with the Agent tool, at `effort: "high"`, in the target repository's checkout.

```text
Run the skill <pr-review> with arguments `<OWNER/REPO>#<PR> --worktree`.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

You run at effort high; use that value in your signature.
The PR implements issue #<issue>. It was written by <implementer agent> through issue-to-pr. Fix requests and your re-check will follow later through this same conversation, so remember your findings.
Final report: verdict (ready to merge, or changes needed), findings (priority, file and line, content), what you posted with URLs, worktree path, checks run and their results.
Also report each thing you noticed but did not raise as a finding: the head SHA you checked, file:line (several allowed; a file alone if it concerns the whole file), what you noticed, why you did not raise it (e.g. out of the issue's scope, no current effect, nice to have), and the related future issue or milestone (or none, or unknown).
```

## Reviewer: re-check

Send it with SendMessage to the same reviewer. For a conflict resolution, say the reviewer should check the new head and include the resolution commit in the implementer's report. Include finding lines only when there were findings to address.

```text
The implementer pushed fixes to PR <OWNER/REPO>#<PR>. Re-check them as a continuation of your review, following <pr-review> with --worktree.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

Implementer's report:
- <finding>: <fixed in SHA / declined because …>: <reply URL>
CI: <state>

Final report: each finding (resolved, or not and why), threads resolved, new findings, what you posted with URLs, checks run and their results, final merge verdict.
Also report each new thing you noticed but did not raise as a finding: the head SHA you checked, file:line (several allowed; a file alone if it concerns the whole file), what you noticed, why you did not raise it (e.g. out of the issue's scope, no current effect, nice to have), and the related future issue or milestone (or none, or unknown).
```

## Reviewer: merge

Send this only when the user gave `--merge`, or approved this merge later in the conversation.

```text
The user approved merging PR <OWNER/REPO>#<PR>. Merge it following <pr-review> with --merge.

The user's language is <language>. Write repository text (commits, PRs, comments) by the repository's conventions, falling back to the user's language. Report and ask questions in English.

Before merging, re-check the merge conditions. If anything changed since your last check (head SHA, CI, unresolved threads, merge state), do not merge; report instead.

Final report: merge result (method, merge commit, PR and issue state) and the pre-merge check.
```

## Answering a question

Resume the same agent. State whose decision the answer is:

- The user's answer: quote the user's words verbatim, then render them in English, naming the chosen option as the agent gave it. A translation alone can shift the intent, and a short reply such as "2で" refers to the options as you relayed them. Leave out the rendering only if the user answered in English and named the option as the agent gave it; a bare "2" in English still needs it.

  ```text
  The user decided:
  > <the user's words, verbatim>
  In English: <rendering that names the chosen option in the agent's terms>
  ```

- When taking a recommendation by default, say "The orchestrator chose your recommendation <answer>. The user has not seen this decision. Record it in the PR (e.g. Review focus or the thread)."
