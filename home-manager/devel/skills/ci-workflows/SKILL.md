---
name: ci-workflows
description: Use when creating, reviewing, or migrating GitHub Actions workflows that may use shared components from pschmitt/ci-workflows.
---

# Shared CI workflows

Use the public [`pschmitt/ci-workflows`](https://github.com/pschmitt/ci-workflows) repository as the source for reusable GitHub Actions workflows, composite actions, and shared scripts. Read its current README and the relevant workflow or action definition before changing a caller; the README is a catalog, not a substitute for the interface in the source.

## Preserve each caller's CI contract

Before editing, inspect all relevant `.github/workflows/*.yml` and `.yaml` files in the consuming repository. Record the existing triggers and path filters, required check/job names, conditions, matrices, permissions, secrets, artifacts, concurrency, and caches that the requested change could affect.

- Keep triggers in the caller. In particular, a `schedule` (cron) trigger belongs on the caller workflow; a reusable workflow called with `workflow_call` does not give the caller a cron trigger.
- Preserve checks and caller-specific behavior while replacing duplicated steps. A reusable workflow call is a job-level replacement, so retain the caller's job id and relevant `needs`, `if`, `with`, `secrets`, and `permissions` settings.
- Compare the shared workflow's current inputs, secrets, outputs, permissions, and matrix behavior with the caller. Grant only the permissions the called workflow requires, and do not assume permissions or secrets flow through automatically.
- Use a shared component only where the behavior genuinely overlaps. Keep repository-specific tests, fixtures, publish gates, release conventions, and build topology in the caller when the shared interface does not cover them.

## Version and migration details

Callers commonly use `uses: pschmitt/ci-workflows/.github/workflows/<name>.yaml@main` and composite actions under `.github/actions/`. `@main` follows mutable shared code: inspect the exact current implementation and consider the consuming repository's compatibility needs before changing a reference or updating a caller. Follow the caller's existing pinning convention unless the task calls for a deliberate change.

The Android workflows and actions were migrated from [`pschmitt/android-app-ci`](https://github.com/pschmitt/android-app-ci). Existing callers can continue using that repository during migration. For repos whose Just imports use `.just/android-app-ci`, preserve that local path as a compatibility alias when updating the submodule URL to `pschmitt/ci-workflows`; do not rename it as incidental cleanup. Read the current [`Android caller guide`](https://github.com/pschmitt/ci-workflows/blob/main/docs/android-ci.md) and provenance notice before changing Android callers. Review the migration for behavior changes, especially publish gates and workflow inputs.

The shared repository does not currently document or provide a PyPI publishing workflow. Do not assume that a PyPI publish action can be placed inside a nested reusable workflow; inspect current GitHub Actions constraints and keep publishing in the caller unless a supported interface is verified.

## Scope and references

Repositories using shared components are not interchangeable. Check the target repository's own instructions, workflows, package layout, and release process; examples in `ci-workflows` are starting points, not a mandate to make every repository identical.

Start with the [`ci-workflows README`](https://github.com/pschmitt/ci-workflows#readme), then use its [Android guide](https://github.com/pschmitt/ci-workflows/blob/main/docs/android-ci.md) or the exact source workflow/action needed. The API and supported behavior can change, so confirm claims against current source when making a change.
