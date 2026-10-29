---
name: merge-bulk
description: Triage and merge batches of Renovate or Dependabot pull requests across repositories, including dependency-related CI failures and notification cleanup. Use for backlog-clearing or bulk dependency-update requests; use github-notifications for ordinary inbox triage.
---

# Merge bulk dependency updates

Use this skill when the user asks to clear a batch of Renovate or Dependabot PRs. Work from the user's requested scope and explicit merge authorization. Keep unrelated notifications and repositories out of scope; honor exclusions such as a named repository.

## Triage and review

- Use `gh` and GitHub's API as the source of truth. Start with unread notifications unless the user asks for historical or all notifications. Capture repository, PR number, title, notification reason, and unread state; group duplicate threads by PR.
- For a backlog-clearing request, notifications are an entry point, not a complete inventory. Also enumerate open Renovate/Dependabot PRs in the requested account or repository set, including PRs without unread notifications. For example, use `gh search prs --owner <owner> --state open --limit 1000 --json repository,number,title,author,url` and filter bot authors after fetching results; partition the search if it reaches GitHub's result cap. Reconcile the inventory against the reviewed, blocked, excluded, and already-closed PRs. If the scope is a user's projects, identify the relevant repositories from GitHub metadata and recent notification history; honor explicit exclusions and do not unarchive archived repositories to make their PRs actionable.
- Inspect each candidate's author, diff/files, head and base, reviews, merge state, and current checks. Treat a PR as a dependency update only after confirming the actual files and changes.
- Review what the dependency does and whether the bump is compatible. Look for major-version changes, release notes, changed runtime behavior, lockfile drift, generated assets, workflow/security changes, and related PRs that supersede or conflict with it.
- For Android projects, inspect the Gradle/catalog/lockfile diff and the relevant Android, emulator, ABI, and Termux jobs. Call out manual or skipped screenshot, Play Store, signing, and release jobs explicitly; their skipped state is not a passing test.
- CI is evidence, not the whole review. Use relevant passing tests/builds plus the diff and upstream context. If checks are absent, queued, or inconclusive, state that plainly and use a targeted remote build or test only when it materially improves confidence.
- When a bump causes a concrete source or test failure, fix the smallest related issue on that PR branch if the user authorized implementation. Keep the dependency update intact, preserve current base-branch changes, and verify the fix with the repository's normal checks.
- Distinguish package/dependency updates from workflow-only updates. Review workflow changes for what they execute and publish; if the authenticated GitHub token lacks the `workflow` scope, leave such PRs open and report the scope blocker instead of switching credentials or trying another push path.

## Builds and parallel work

- Avoid expensive builds on the local machine. Follow repository `AGENTS.md` instructions; for this user's Android and NixOS projects, prefer `rofl-13` for builds and Nix evaluation. Do not start expensive local work just to replace pending CI.
- Never start expensive local builds when the user has prohibited them. Use the requested remote builder (currently `rofl-13`) and its documented per-project build directory; do not duplicate a CI build that is already running unless a targeted local/remote result would change the decision.
- Use GitHub-hosted checks when they cover the relevant target. Distinguish checks for the changed dependency from unrelated jobs in a broad matrix.
- Parallelize independent repository reviews only when the user asks for agents or parallel work. Keep agents on disjoint PRs/repositories, share the same merge and local-build constraints, and reconcile their final PR states before notification cleanup.

## Merge decisions

- Merge only when the user explicitly authorized merging. Use the repository's normal method, usually squash. Do not bypass branch protection, required checks, reviews, or repository policy with administrator privileges.
- Do not merge conflicts, stale heads, uncertain merge states, or PRs with unresolved review concerns. Rebase or update a bot branch only when needed to preserve a safe, minimal dependency diff; use a lease when force-pushing and sign commits when repository practice requires it.
- Inspect workflow, permission, secret, deployment, or access-control changes separately from ordinary package bumps. Do not merge security-sensitive changes under ordinary dependency-update authorization. If GitHub reports that the OAuth app lacks `workflow` scope, leave the PR open and report that exact blocker; do not try another credential or bypass.
- Approve a held GitHub Actions run only after checking the PR contents, workflow revision and event, token permissions, and external side effects such as package publication or bot pushes. Allow only expected, scoped effects; do not approve untrusted code merely to obtain green checks.
- If branch policy waits on checks, continue monitoring when practical. Use auto-merge only if repository policy supports it and the user authorized the resulting merge; never use it to evade a failed or required check.

## Notifications and reporting

- After verifying a PR is merged or closed, mark its notification thread done with `gh api -X DELETE notifications/threads/<thread-id>`. Clear all relevant threads for that PR, including duplicate threads. Leave open or blocked PR threads unread; do not clear unrelated mentions, issues, releases, or excluded repositories.
- If the user asks for periodic Signal updates, send a concise update about once per hour and a short completion summary. Report merged PRs, concrete fixes, notification threads cleared, and any blockers that remain. Never imply that a pending or blocked PR was merged.
