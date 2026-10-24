# Receiving PR updates

Read this before monitoring with `--watch`, when starting to monitor the PR after posting the review (step 4 in SKILL.md), when checking new commits and replies (with or without `--watch`), and when looking for or waiting for a PR from an issue (step 0).

Sections A, B and "Both cases" apply only with `--watch`. Without it, do the checks in "Checking new commits and replies" once and end, as "Monitoring (`--watch`)" in SKILL.md describes.

## Can this environment monitor?

Check this when `--watch` is given, before starting the work. Monitoring is supported only if something wakes this session again after the reply ends, because the checks are 5–10 minutes apart and the author's responses take longer than one reply:

- **Supported**: a PR event subscription (A below), or a scheduled wakeup or loop the agent can set up itself (e.g. `/loop`, `ScheduleWakeup`, a trigger or a cron tool the session offers).
- **Not supported**: nothing can restart the session after the reply ends. For example, Codex CLI has no built-in way to run on a schedule; it runs again only when started from outside (e.g. `codex exec` from cron). A `sleep` loop inside one reply does not count: commands time out and the reply ends long before 60 minutes without activity (below).

If it is not supported, say so at the start, before reviewing, so the user does not wait for monitoring that will not happen. Then do the one pass as without `--watch`. Example:

```
--watch is not supported in this environment: nothing can wake this session after the reply ends, so the PR will not be monitored.
I will post the review and report once. To check the responses later, ask again (e.g. "re-check PR #51"), or run this skill periodically from outside (e.g. cron).
```

## A. When PR event subscriptions are available (Claude Code on the web, etc.)

If the session has a way to subscribe to the PR's GitHub activity (the one auto-fix uses) and the Claude GitHub App is installed on the repository, subscribe to the PR. Replies to review comments and CI failures then arrive in the session as events; handle each as soon as it arrives, without waiting for the next scheduled check.

Caveats:

- **Never fix anything automatically.** The mechanism exists for auto-fix (the author side pushing fixes automatically). This skill uses it as the reviewer, so it never changes code or pushes when an event arrives. If the only way to subscribe is "turn on auto-fix", use it only after stating clearly that nothing will be fixed, or switch to B.
- **Some events do not arrive.** Mostly review comments and CI failures arrive. New pushes, CI success and new conflicts may not. The author may push without replying, so **also check on the schedule in B**.
- **Your own posts become events.** This skill's replies and reviews may arrive as events too. Ignore events from comments with the `<!-- pr-review -->` marker.

## B. When event subscriptions are not available

Check with a scheduled wakeup or loop the environment offers (`/loop`, `ScheduleWakeup`, etc.) on this schedule, which `issue-to-pr` uses too:

- **Time counts from the start of monitoring** (when the review is posted, or the start of the `--watch` run when waiting for a PR from an issue), and **restarts from zero at each new author activity**: a new commit, a reply in a thread or a PR comment without the `<!-- pr-review -->` marker, an update to the PR description, or the PR being created or marked ready for review. Your own reviews and replies do not restart it.
- Check **every 5 minutes** for the first 20 minutes, then **every 10 minutes** until 60 minutes.
- **Monitoring stops after 60 minutes without author activity**, so a session is not held while nobody responds.
- **Pending CI checks** are not bound to that schedule: you are checking a machine, not waiting for a person, so while you wait for them (e.g. before deciding on a merge), check every 30–60 s.

## Both cases

- On every check, look at changes of the head SHA, new comments in threads, and the CI state. When woken by an event, look at the whole PR state, not only that event, because events can be duplicated or arrive out of order.
- **Stop monitoring** when the PR is merged, when it is closed, when the merge conditions are met without `--merge`, or after 60 minutes without author activity. When stopping, also unsubscribe, and report the state at that point (unresolved threads, responses still awaited) to the user.

## Checking new commits and replies (step 4)

### On new commits

- Read the diff from the last checked SHA to the new one. A new session (e.g. a re-check without `--watch`) takes it from the `commit_id` of this skill's latest review with the `<!-- pr-review -->` marker, which every review, Approve included, pins to the SHA it checked ("Posting a review" in `github-commands.md`); if there is none, review the whole diff again.
- Check that unresolved findings are fixed and that the fixes add no new problems.
- Post new problems as new findings with priorities, as one review again. **Post them before resolving existing threads**: with the same account, `issue-to-pr` treats "all threads resolved" as done, so resolving first could end its monitoring before the new findings arrive.
- If an existing finding's fix is sound, reply with the commit that fixed it, then resolve the thread. If not, reply with the reason and leave it open.

### On replies in threads

Handle each reply as in "Replies" in `review-protocol.md`. Also: a `P0` cannot be deferred, so reply saying so and leave the thread open; never create the deferral issue yourself; ask the user when you cannot judge a decline.

Resolve only threads this skill opened (with the marker). Do not touch other reviewers' threads.

## Waiting for a PR from an issue (step 0)

Without `--watch`, look for the PR once ("Finding the PR" and "several open candidates" below): if it exists, continue with the review; if it is a draft, report that it is still a draft and end; if there is none, report that there is no PR yet and end. With `--watch`, wait for it as below.

- **Finding the PR**: look for PRs linked to the issue (PRs that will close it with `Closes #123` etc., and PRs referencing it in its timeline). Commands: "Finding the PR for an issue" in `github-commands.md`.
- **Interval**: the schedule in B (5 minutes, then 10 minutes, until 60 minutes without activity). Issue updates do not arrive as PR events, so use periodic checks.
- **If the PR found is a draft**, treat it as work in progress and keep waiting until it is ready for review, without asking the user (they already asked to wait for the PR).
- **If there are several open candidates**, ask the user which to review.
- **Stop** after 60 minutes without a PR, or when the issue is closed without a PR, and report to the user.
- When the PR is found, say briefly in chat which PR you will review, then start the review.
