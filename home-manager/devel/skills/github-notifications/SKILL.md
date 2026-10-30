---
name: github-notifications
description: Triage GitHub notifications across pull requests, issues, and related activity; prioritize mentions and review work and report on Renovate PRs. Use when the user asks to go through, triage or clear their GitHub notifications. To review or merge Renovate/Dependabot PRs, use merge-prs.
---

# GitHub notifications

Use the GitHub CLI (`gh`) to inspect the authenticated user's notifications and the referenced pull requests or issues. Prefer direct GitHub API/CLI data over assumptions, deduplicate multiple notifications for the same item, and finish with a concise summary containing clickable links and every action taken.

## Modes and authorization

- Default mode is read-only triage: fetch notifications, inspect PRs, review diffs and CI, and report. Do not merge, approve, comment, request changes, or mark notifications read.
- Merging is out of scope here: if the user asks to merge PRs (for example “yolo merge the safe ones”), switch to the `merge-prs` skill.
- Treat “review these PRs” as a request for analysis and a recommendation unless the user separately asks to submit a GitHub review.
- Mark notifications read only when explicitly requested. Preserve unread state for everything else.
- If a mutation is requested but the target, merge method, or scope is ambiguous, stop that mutation and report the ambiguity.

## Triage workflow

1. Verify GitHub authentication with `gh auth status`. If it fails or the required repository is inaccessible, report the blocker without attempting workarounds that expose credentials.
2. Fetch the relevant notification set with `gh api --paginate notifications` for unread notifications. Use `notifications?all=true` only when the user asks for all or historical notifications. Capture each notification's repository, subject type/title/API URL, reason, unread state, and update time.
3. Prioritize direct review requests and assignments first; then direct mentions or requested changes on PRs/issues; then issue state changes and other work needing a response; then failing or newly updated Renovate PRs; then other participating PRs/issues; finally subscriptions, releases, and low-signal notifications. Group multiple notification threads that point to the same item.
4. Resolve each PR or issue to its canonical web URL. For PRs inspect at least title, author, state, draft status, base/head branches, labels, requested reviews, current reviews, mergeability, merge state, changed files, and status checks. Useful commands include `gh pr view <url> --json ...`, `gh pr checks <url>`, and `gh pr diff <url>`.
5. For PRs requiring human review, summarize the actual change and call out concrete correctness, compatibility, security, or operational risks. Do not infer that green CI means the change is safe; distinguish “CI passed” from “code reviewed.”
6. For issues, inspect title, state, author, assignees, labels, milestone, body, recent comments/events, linked or closing PRs, and the notification reason. Summarize what changed since the previous notification and what response or decision appears to be needed. Use `gh issue view <url> --comments` or the corresponding API when the CLI does not expose enough timeline context.
7. For unsupported or less common subjects such as Discussions, releases, commits, or security alerts, fetch enough metadata to explain why the notification exists and whether it needs action. Do not silently drop a notification; group low-signal items with counts and links when appropriate.

## Renovate and Dependabot PRs

Report bot PRs (identified by author, not title) with their CI and merge state, but do not review or merge them here. When the user wants them reviewed, fixed or merged, load the `merge-prs` skill; it owns the review, fix and merge rules and the notification cleanup for merged PRs.

## Review and notification state

Inspect review requests, submitted reviews, conversations, and the PR timeline when deciding whether something needs the user's attention. For issue mentions, identify the relevant comment or event and summarize the requested follow-up rather than merely repeating the issue body. Do not submit an approval, comment, label change, assignment, or issue state change merely to clear a notification. If asked to mark notifications read, do so only after processing and record which threads were changed. Threads of PRs that are already `MERGED` or `CLOSED` may be marked done when the user asks to clear notifications, using `gh api -X DELETE notifications/threads/<thread-id>` (`PATCH` only marks read); verify the PR state first and never mark open PRs, issues, review requests, or mentions that still need a response.

## Final report

Always end with a self-contained summary. Include:

- the scope checked (unread vs all notifications, repositories, and timestamp if useful);
- a PR and issue summary with direct links, category/reason, author/assignees, current state, relevant CI or timeline context, and recommendation;
- every mutation actually performed, including merge method, merged PR links, comments/reviews, or notification threads marked read;
- every skipped or blocked action with the concrete reason;
- low-signal or non-actionable notifications as a short grouped remainder unless the user asks for deeper handling.

Use explicit wording such as “merged,” “not merged,” “reviewed only,” or “blocked by failing check.” Never imply that an action happened when it was only recommended.
