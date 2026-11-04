# CI

## Builds

nixbot is the self-hosted CI for x86_64. It builds the attribute named in
[`nixbot.toml`](../nixbot.toml), which `herculesCI` in
[`flake.nix`](../flake.nix) defines: host systems, the ISO image and the
supported custom packages.

GitHub's ARM runners build the aarch64 outputs in
[`nix-build.yaml`](../.github/workflows/nix-build.yaml).

Both upload their results to the binary cache. See
[services/harmonia/README.md](../services/harmonia/README.md) for how the cache
delivers them.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| [`nix-build`](../.github/workflows/nix-build.yaml) | Push, pull request, weekly | Build and upload the outputs |
| [`lint`](../.github/workflows/lint.yaml) | Push, pull request | Lint the repository |
| [`flake-lock`](../.github/workflows/flake-lock.yaml) | Daily | Update `flake.lock` |
| [`nix-update`](../.github/workflows/nix-update.yaml) | Daily | Open a pull request with package updates |
| [`nix-update-merge`](../.github/workflows/nix-update-merge.yaml) | After builds, hourly | Merge package updates that passed their checks |
| [`nix-update-rebase`](../.github/workflows/nix-update-rebase.yaml) | Push to `main` | Keep open package update pull requests rebased |
| [`nix-rpi-images`](../.github/workflows/nix-rpi-images.yaml) | Weekly | Build Raspberry Pi images |
| [`nix-systempackages-diff`](../.github/workflows/nix-systempackages-diff.yaml) | Pull request | Compare `systemPackages` between revisions |

## Dependency updates

Renovate opens pull requests for pinned container images and other dependencies,
as configured in [`renovate.json`](../renovate.json).
