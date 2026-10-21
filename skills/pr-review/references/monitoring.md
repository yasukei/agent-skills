# Receiving PR updates

Read this when starting to monitor the PR after posting the review (step 4 in SKILL.md), when checking new commits and replies, and when waiting for a PR to be created from an issue (step 0).

## A. When PR event subscriptions are available (Claude Code on the web, etc.)

If the session has a way to subscribe to the PR's GitHub activity (the one auto-fix uses) and the Claude GitHub App is installed on the repository, subscribe to the PR. Replies to review comments and CI failures then arrive in the session as events.

Caveats:

- **Never fix anything automatically.** The mechanism exists for auto-fix (the author side pushing fixes automatically). This skill uses it as the reviewer, so it never changes code or pushes when an event arrives. If the only way to subscribe is "turn on auto-fix", use it only after stating clearly that nothing will be fixed, or switch to B.
- **Some events do not arrive.** Mostly review comments and CI failures arrive. New pushes, CI success and new conflicts may not. The author may push without replying, so **also check every 15 minutes as in B**.
- **Your own posts become events.** This skill's replies and reviews may arrive as events too. Ignore events from comments with the `<!-- pr-review -->` marker.

## B. When event subscriptions are not available

Check **every 15 minutes** with whatever waiting mechanism Claude Code offers (`/loop`, `ScheduleWakeup`, `sleep` in Bash, etc.).

## Both cases

- On every check, look at changes of the head SHA, new comments in threads, and the CI state. When woken by an event, look at the whole PR state, not only that event, because events can be duplicated or arrive out of order.
- **Stop monitoring** when the PR is merged, when it is closed, when the merge conditions are met without `--merge`, or after 24 hours with no activity. When stopping, also unsubscribe, and report the state at that point (unresolved threads, responses still awaited) to the user.

## Checking new commits and replies (step 4)

### On new commits

- Read the diff from the last checked SHA to the new one.
- Check that unresolved findings are fixed and that the fixes add no new problems.
- Post new problems as new findings with priorities, as one review again. **Post them before resolving existing threads**: with the same account, `issue-to-pr` treats "all threads resolved" as done, so resolving first could end its monitoring before the new findings arrive.
- If an existing finding's fix is sound, reply with the commit that fixed it, then resolve the thread. If not, reply with the reason and leave it open.

### On replies in threads

Handle each reply as in "Replies" in `review-protocol.md`. Also: a `P0` cannot be deferred, so reply saying so and leave the thread open; never create the deferral issue yourself; ask the user when you cannot judge a decline.

Resolve only threads this skill opened (with the marker). Do not touch other reviewers' threads.

## Waiting for a PR from an issue (step 0)

- **Finding the PR**: look for PRs linked to the issue (PRs that will close it with `Closes #123` etc., and PRs referencing it in its timeline). Commands: "Finding the PR for an issue" in `github-commands.md`.
- **Interval**: creating a PR often takes a while, so check about **every 30 minutes**. Issue updates do not arrive as PR events, so use periodic checks.
- **If the PR found is a draft**, treat it as work in progress and keep waiting until it is ready for review, without asking the user (they already asked to wait for the PR).
- **If there are several open candidates**, ask the user which to review.
- **Stop** after 24 hours without a PR, or when the issue is closed without a PR, and report to the user.
- When the PR is found, say briefly in chat which PR you will review, then start the review.
