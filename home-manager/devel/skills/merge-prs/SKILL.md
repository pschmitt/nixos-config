---
name: merge-prs
description: Review and merge GitHub pull requests, by default Renovate and Dependabot dependency updates, fixing what the bump breaks. Works in two modes - a bulk sweep of all open bot PRs across the user's repositories, or a focused review of a single PR or repository when given a link. Use for backlog-clearing, "review/merge this PR", or "merge the renovate PRs"; use github-notifications for ordinary inbox triage.
---

# Review and merge pull requests

Use this skill when the user asks to review or merge pull requests. For inbox triage and notification state, work together with `github-notifications`. Unless told otherwise, the target is Renovate and Dependabot PRs, and the goal is to get them merged, not only reviewed: if a bump needs a fix to pass, make the fix. Honor explicit exclusions such as a named repository.

## Modes

- **Bulk:** no link given ("clear the renovate PRs", "merge the dependency updates"). Build the inventory described below and work through every PR in scope.
- **Focused:** the user gives a PR, repository or issue link. Review only that target, in more depth: read the full diff, upstream release notes and the discussion, and report a clear recommendation. A focused request on a non-bot PR is a review unless the user asks for a merge.
- **Merge intent:** in repositories owned by the user's personal account (`pschmitt/*`), merge qualifying bot PRs by default; the request to review or merge them is the authorization. For human-authored PRs, or when the user only asked to "look at" or "review", stop at a recommendation and do not merge or submit a GitHub review.
- **Organization and third-party repositories:** never merge in repositories under an organization or any owner other than the user's personal account (for example zinit, wiit, pykeepass) without the user's explicit consent for that repository, organization or PR. A generic "merge the renovate PRs" does not cover them. Listing, reviewing, fixing-in-a-branch proposals and recommendations are fine; report them as "ready to merge, awaiting your OK" and ask. Consent given for one organization or run does not carry over to another.

## Inventory (bulk mode)

- Use `gh` and GitHub's API as the source of truth. Notifications are an entry point, not a complete inventory. Also enumerate open Renovate/Dependabot PRs in the requested account or repository set, including PRs without unread notifications. For example, use `gh search prs --owner <owner> --state open --limit 1000 --json repository,number,title,author,url` and filter bot authors after fetching results; partition the search if it reaches GitHub's result cap.
- Capture repository, PR number, title, author, notification reason and unread state; group duplicate threads by PR. Reconcile the inventory against the reviewed, merged, blocked, excluded and already-closed PRs before reporting.
- If the scope is a user's projects, identify the relevant repositories from GitHub metadata and recent notification history. Skip archived repositories entirely (check `isArchived`; `gh search prs` can return their PRs): do not review or merge their PRs, never unarchive a repository to make a PR actionable, and mention them at most as a short "skipped, archived" line in the report.

## Review

- Identify bot PRs by author (`renovate[bot]`, `dependabot[bot]`) and confirm the actual files; never go by title alone. Inspect head and base, reviews, merge state, draft state and current checks.
- Review what the dependency does and whether the bump is compatible. Look for major-version or pre-release changes, release notes, changed runtime behavior, lockfile drift, generated assets, workflow/security changes, and related PRs that supersede or conflict with it. Dependabot security-advisory PRs get priority.
- Distinguish package updates from workflow-only updates. Review workflow changes for what they execute and publish. If the GitHub token lacks the `workflow` scope, leave such PRs open and report that exact blocker; do not switch credentials or try another push path.
- CI is evidence, not the whole review. Use relevant passing tests/builds plus the diff and upstream context. If checks are absent, queued or inconclusive, say so and run a targeted remote build or test only when it materially improves confidence. Distinguish checks for the changed dependency from unrelated jobs in a broad matrix.
- For Android projects, inspect the Gradle/catalog/lockfile diff and the relevant Android, emulator, ABI and Termux jobs. Call out manual or skipped screenshot, Play Store, signing and release jobs explicitly; skipped is not passing.

## Fixing

- When a bump causes a concrete source, lockfile or test failure, fix it on the PR branch. Keep the dependency update intact, make the smallest related change, preserve current base-branch changes, and verify with the repository's normal checks. Fixing is the default for bot PRs; ask first only when the fix is large, changes behavior beyond the bump, or touches security-sensitive code.
- If a bot branch is behind or conflicting, ask the bot to rebase (`@dependabot rebase`, or the Renovate rebase checkbox) first. Rebase or update it yourself only when that is quicker or the bot cannot; use a lease when force-pushing and sign commits when repository practice requires it (see the GPG rules in the global context).
- If a fix is not feasible (upstream bug, needs a design decision, several bumps must land together), leave the PR open and report the concrete blocker with a suggested next step.

## Builds and parallel work

- Avoid expensive builds on the local machine. Follow repository `AGENTS.md`; for this user's Android and NixOS projects, prefer `rofl-13` and its documented per-project build directory for builds and Nix evaluation. Do not duplicate a CI build that is already running unless a targeted result would change the decision, and never start expensive local builds when the user has prohibited them.
- Parallelize independent repository reviews only when the user asks for agents or parallel work. Keep agents on disjoint PRs/repositories, share the same merge and build constraints, and reconcile their final PR states before notification cleanup.

## Merge decisions

Merge a PR when all of these hold:

- the repository is in scope for merging (personal account, or explicit consent given for it);
- open, non-draft, from the expected author;
- required CI successful on the current head commit, including after any fix you pushed;
- clean and mergeable, not stale or behind when branch protection requires updating;
- required approvals present, with no unresolved blocking review concern;
- no unexplained source behavior change, and no workflow, permission, secret, deployment or access-control change unless the user explicitly includes that class of update.

Major, breaking or pre-release bumps are not auto-skipped when the user asked to merge: review them closely, fix what breaks, and merge only when you are confident; otherwise report why they were held.

- Use the repository's normal method, usually `gh pr merge <url> --squash`. Do not delete branches unless the repository's usual flow does.
- Never bypass branch protection, required checks, reviews or repository policy, and never use administrator privileges. Do not merge conflicts, stale heads or uncertain (`UNKNOWN`) merge states.
- Approve a held GitHub Actions run only after checking the PR contents, workflow revision and event, token permissions and external side effects such as package publication or bot pushes. Do not approve untrusted code merely to obtain green checks.
- If branch policy waits on checks, keep monitoring when practical. Use auto-merge only if repository policy supports it; never use it to evade a failed or required check. If a merge command fails, do not retry with a different strategy silently.

## Notifications and reporting

- Load the `github-notifications` skill for notification handling (fetching, deduplicating, what may be cleared). After verifying a PR is merged or closed, mark its notification threads done with `gh api -X DELETE notifications/threads/<thread-id>` (`PATCH` only marks read). Clear all threads for that PR, including duplicates. Leave open or blocked PR threads unread; do not clear unrelated mentions, issues, releases or excluded repositories.
- If the user asks for periodic Signal updates, load `signal-notify` and send a concise update about once per hour plus a short completion summary.
- End with a summary with links: scope, merged PRs, fixes pushed, notification threads cleared, and each blocked or held PR with its exact blocker. Never imply that a pending or blocked PR was merged.
