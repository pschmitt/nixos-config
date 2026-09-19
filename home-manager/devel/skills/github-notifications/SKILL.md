---
name: github-notifications
description: Triage GitHub notifications across pull requests, issues, and related activity; prioritize mentions and review work, check Renovate CI, and optionally merge safe PRs.
---

# GitHub notifications

Use the GitHub CLI (`gh`) to inspect the authenticated user's notifications and the referenced pull requests or issues. Prefer direct GitHub API/CLI data over assumptions, deduplicate multiple notifications for the same item, and finish with a concise summary containing clickable links and every action taken.

## Modes and authorization

- Default mode is read-only triage: fetch notifications, inspect PRs, review diffs and CI, and report. Do not merge, approve, comment, request changes, or mark notifications read.
- An explicit request such as “yolo merge the safe ones” authorizes merging qualifying PRs during that run. It does not authorize unrelated comments, approvals, branch deletion, or changes to non-PR issues.
- Treat “review these PRs” as a request for analysis and a recommendation unless the user separately asks to submit a GitHub review.
- Mark notifications read only when explicitly requested. Preserve unread state otherwise.
- If a mutation is requested but the target, merge method, or scope is ambiguous, stop that mutation and report the ambiguity.

## Triage workflow

1. Verify GitHub authentication with `gh auth status`. If it fails or the required repository is inaccessible, report the blocker without attempting workarounds that expose credentials.
2. Fetch the relevant notification set with `gh api --paginate notifications` for unread notifications. Use `notifications?all=true` only when the user asks for all or historical notifications. Capture each notification's repository, subject type/title/API URL, reason, unread state, and update time.
3. Prioritize direct review requests and assignments first; then direct mentions or requested changes on PRs/issues; then issue state changes and other work needing a response; then failing or newly updated Renovate PRs; then other participating PRs/issues; finally subscriptions, releases, and low-signal notifications. Group multiple notification threads that point to the same item.
4. Resolve each PR or issue to its canonical web URL. For PRs inspect at least title, author, state, draft status, base/head branches, labels, requested reviews, current reviews, mergeability, merge state, changed files, and status checks. Useful commands include `gh pr view <url> --json ...`, `gh pr checks <url>`, and `gh pr diff <url>`.
5. For PRs requiring human review, summarize the actual change and call out concrete correctness, compatibility, security, or operational risks. Do not infer that green CI means the change is safe; distinguish “CI passed” from “code reviewed.”
6. For issues, inspect title, state, author, assignees, labels, milestone, body, recent comments/events, linked or closing PRs, and the notification reason. Summarize what changed since the previous notification and what response or decision appears to be needed. Use `gh issue view <url> --comments` or the corresponding API when the CLI does not expose enough timeline context.
7. For unsupported or less common subjects such as Discussions, releases, commits, or security alerts, fetch enough metadata to explain why the notification exists and whether it needs action. Do not silently drop a notification; group low-signal items with counts and links when appropriate.

## Renovate handling

Identify Renovate PRs by the author (`renovate[bot]`/Renovate), bot metadata, or repository conventions—not by title alone. For each one:

- Check all required checks and the latest commit status. Pending, failing, cancelled, or unknown required checks are blockers. Explain skipped or neutral checks when they affect confidence.
- Check `mergeStateStatus`, `mergeable`, draft state, review requirements, and whether the branch is behind the base branch. Do not merge conflicts, stale/behind branches, or state `UNKNOWN` as safe.
- Inspect the diff and dependency metadata/lockfile changes. Confirm the update is scoped to dependency maintenance and look for major-version or breaking-change notes, changed runtime behavior, changed build inputs, or security-sensitive workflow/container/toolchain changes.
- Use CI as the primary build/test evidence. Run a local build only when CI is absent, inconclusive, or the user requests it; do not claim a local verification that was not performed.
- If the update is straightforward, CI is green, mergeability is clean, required approvals are present or not required by branch protection, and no substantive concern appears in the diff, it may be recommended for merging. It may be merged only in an explicitly authorized merge mode.

## Yolo-merge safety gates

When explicit merge authorization is present, merge only PRs that satisfy every applicable gate:

- open, non-draft PR from the expected author/source;
- required CI successful on the current head commit;
- clean and mergeable, not behind when branch protection requires updating;
- required approvals present, with no apparent unresolved blocking review concern;
- small, dependency-only, well-scoped change with no unexplained source behavior changes;
- no major/breaking/pre-release update or other risk visible in the PR description, release notes, labels, or diff;
- no workflow, access-control, secret, deployment, or other security-sensitive change unless the user explicitly includes that class of update.

If any gate is uncertain, leave the PR unmerged and state the exact blocker. Never bypass branch protection, failing checks, required reviews, merge conflicts, or repository policy. Prefer the repository's normal squash method (`gh pr merge <url> --squash`) and do not delete branches unless explicitly requested or clearly part of the repository's established merge command. If a merge command fails, do not retry with a different strategy silently.

## Review and notification state

Inspect review requests, submitted reviews, conversations, and the PR timeline when deciding whether something needs the user's attention. For issue mentions, identify the relevant comment or event and summarize the requested follow-up rather than merely repeating the issue body. Treat unresolved or unclear reviewer concerns as blockers for auto-merge. Do not submit an approval, comment, label change, assignment, or issue state change merely to clear a notification. If asked to mark notifications read, do so only after processing and record which threads were changed.

## Final report

Always end with a self-contained summary. Include:

- the scope checked (unread vs all notifications, repositories, and timestamp if useful);
- a PR and issue summary with direct links, category/reason, author/assignees, current state, relevant CI or timeline context, and recommendation;
- every mutation actually performed, including merge method, merged PR links, comments/reviews, or notification threads marked read;
- every skipped or blocked action with the concrete reason;
- low-signal or non-actionable notifications as a short grouped remainder unless the user asks for deeper handling.

Use explicit wording such as “merged,” “not merged,” “reviewed only,” or “blocked by failing check.” Never imply that an action happened when it was only recommended.
