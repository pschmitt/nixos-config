# CI

## Builds

Circus evaluates [`circusJobs`](../flake.nix) for x86_64 and aarch64,
including host systems, images, packages and flake checks. It dispatches native
ARM jobs to ephemeral GitHub Actions builders and reports results to GitHub.
The publishing runner publishes built ISO and worker images from the cache.

Circus effects publish phone system closures and update their upgrade pins.
The [GitHub Nix build workflow](../.github/workflows/nix-build.yaml) remains
available for manual recovery.
See [the binary cache documentation](../services/harmonia/README.md) for how
hosts download build results.

The LAN cache mirror looks up successful Circus host outputs for the current
`main` commit and pulls their signed closures. It keeps the existing local
roots until replacement builds are available. See the [Circus service
configuration](../services/circus/README.md) for details.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| [`nix-build`](../.github/workflows/nix-build.yaml) | Manual | Full build matrix for recovery |
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
