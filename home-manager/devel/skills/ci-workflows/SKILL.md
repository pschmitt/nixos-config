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

Use `@main` for every GitHub workflow or action reference into `pschmitt/ci-workflows`, for example `pschmitt/ci-workflows/.github/workflows/<name>.yaml@main` and `pschmitt/ci-workflows/.github/actions/<name>@main`. Raw helper URLs should use the `main` branch too, such as `https://raw.githubusercontent.com/pschmitt/ci-workflows/main/scripts/<name>`. This avoids Renovate PRs for shared component updates. Do not apply this rule to Nix flake inputs or Git submodule pins; follow their separate pinning policies.

`@main` and raw `main` URLs follow mutable shared code. Inspect the exact current implementation and consider the consuming repository's compatibility needs before changing or adopting a shared component update. Do not replace these shared refs with tags or commit SHAs unless the user explicitly asks for that policy change.

The Android workflows and actions were migrated from [`pschmitt/android-app-ci`](https://github.com/pschmitt/android-app-ci). Existing callers can continue using that repository during migration. For repos whose Just imports use `.just/android-app-ci`, preserve that local path as a compatibility alias when updating the submodule URL to `pschmitt/ci-workflows`; do not rename it as incidental cleanup. Read the current [`Android caller guide`](https://github.com/pschmitt/ci-workflows/blob/main/docs/android-ci.md) and provenance notice before changing Android callers. Review the migration for behavior changes, especially publish gates and workflow inputs.

The shared repository does not currently document or provide a PyPI publishing workflow. PyPA's current [`gh-action-pypi-publish` guidance](https://github.com/pypa/gh-action-pypi-publish#non-goals) says Trusted Publishing is unsupported inside reusable workflows, and invoking the action from a composite action is unsupported and untested. Keep that publish action in a dedicated top-level caller job with scoped `id-token: write` permission, separate from build and test jobs. Recheck upstream guidance before implementation because support can change.

## Nix builds: nixbot for x86_64, GitHub for aarch64

For a repository with a flake, x86_64-linux packages and checks build on the
self-hosted nixbot; aarch64-linux builds natively on GitHub's arm runners
through `nix-aarch64.yaml`, which pushes to the niks3 cache with a GitHub OIDC
token. Do not build aarch64 on nixbot (it would emulate) or x86_64 Nix outputs
in GitHub Actions, except checks that need `/dev/kvm` (NixOS VM tests), which
only the GitHub runners have. Copy rbw, browser-daemon or monarch.

To onboard a repository:

1. Flake: expose `hydraJobs.x86_64-linux.{packages,checks}` and remove KVM
   checks there, e.g.
   `checks = builtins.removeAttrs (self.checks.${system} or { }) [ "nixos" ];`.
2. Repository root: `nixbot.toml` containing `attribute = "hydraJobs"`, and a
   committed `flake.lock`: nixbot evaluates in pure mode and cannot create one.
   To build an existing output without changing the flake, use a dotted path
   such as `attribute = "packages.x86_64-linux"`, or
   `"devShells.x86_64-linux"` for a flake without packages. The default
   attribute is `checks`.
3. Caller job, in a workflow triggered on pushes to main and pull requests:
   ```yaml
   nix-aarch64:
     permissions:
       contents: read
       id-token: write
     uses: pschmitt/ci-workflows/.github/workflows/nix-aarch64.yaml@main
     with:
       exclude-checks: '["nixos"]'
       pin-prefix: gh-<repo>-main
     secrets:
       s3_store: ${{ secrets.NIKS3_S3_STORE }}
       s3_access_key: ${{ secrets.NIKS3_S3_ACCESS_KEY }}
       s3_secret_key: ${{ secrets.NIKS3_S3_SECRET_KEY }}
   ```
4. GitHub settings, per repository: variable `NIKS3_SERVER_URL`, and secrets
   `NIKS3_S3_STORE` (the substituter URL from the private `nix-cache` profile)
   and `NIKS3_S3_ACCESS_KEY`/`NIKS3_S3_SECRET_KEY` (the read-only key,
   `niks3/client-*` in the private shared SOPS file). Pipe values from `sops -d`
   straight into `gh secret set` under `set -o pipefail` and refuse empty
   values; a failed decrypt otherwise stores an empty secret.
5. Private NixOS config: add the repository to `githubRepos` in
   `services/niks3.nix` with `pins = "gh-<repo>-main-*"` (add `subject` when
   `gh api repos/OWNER/REPO/actions/oidc/customization/sub` reports
   `use_immutable_subject: true`), and to `repoAllowlist` in
   `services/nixbot.nix`. Deploy the niks3 and nixbot hosts (see the private
   `brkn-infra` skill) after `bump my privates`.
6. Enable the project. The allowlist only registers it, disabled, and nothing
   builds until then. `POST /api/repos/github/OWNER/REPO/enable` on nixbot needs
   an admin login and an `Origin` header; it also registers the webhook. Use
   `browser_fetch` from a signed-in session (`browser-login` skill) and fill the
   TOTP code, since GitHub's default sign-in prompts the user's phone. Evaluations
   run one at a time, so expect a queue after enabling many repositories.
7. README: put the nixbot badge first in the badge row.

## Docker images

`docker-build.yaml` builds every platform under QEMU: fine for images that
only install packages, far too slow for images that compile Rust or other
native code on arm64. For those, use `docker-native.yaml`, which builds each
platform on a native runner, pushes by digest and merges one manifest per
registry (tags `latest`, `sha-<commit>`, the branch, and the version on tag
pushes; GHCR attestation). The caller keeps its triggers (including a
`schedule` for security rebuilds) and passes `publish`, for example
`${{ github.event_name != 'pull_request' && github.ref == 'refs/heads/main' }}`.
luks-ssh-unlock is a caller; rbw still has its own equivalent `docker.yaml`.

GitHub serves a workflow's `badge.svg` (and shields.io its status) only once
the workflow file exists on the default branch; on a feature branch a badge
for a new workflow returns 404 and READMEs show the alt text. That fixes
itself on merge; it is not a broken URL.

## Scope and references

Repositories using shared components are not interchangeable. Check the target repository's own instructions, workflows, package layout, and release process; examples in `ci-workflows` are starting points, not a mandate to make every repository identical.

Start with the [`ci-workflows README`](https://github.com/pschmitt/ci-workflows#readme), then use its [Android guide](https://github.com/pschmitt/ci-workflows/blob/main/docs/android-ci.md) or the exact source workflow/action needed. The API and supported behavior can change, so confirm claims against current source when making a change.
