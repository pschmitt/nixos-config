# Architecture

See the [organization audit plan](nix-organization-plan.md) for completed cleanup,
ownership decisions and validation gates.

## Repository layout

| Path | Contents |
| --- | --- |
| `flake.nix` | Inputs, the host list and all flake outputs |
| `hosts/<host>/` | One directory per host, with `default.nix` as its entrypoint |
| `profiles/base/` | Common role baseline; minimal images can bypass it |
| `profiles/features/` | Optional capabilities: `containers`, `desktop`, `development`, `diagnostics`, `network`, `work` |
| `profiles/specializations/` | Machine classes and roles: `server`, `laptop`, `workstation`, `rpi` and others |
| `profiles/hardware/` | Hardware-specific snippets |
| `modules/` | Shared NixOS modules and option definitions |
| `modules/home-manager/` | Shared Home Manager modules |
| `home-manager/` | The home config tree, see [its README](../home-manager/README.md) |
| `services/` | Service modules |
| `pkgs/`, `overlays/` | Custom packages and nixpkgs overlays |
| `android/` | Termux environments built with Nix |
| `templates/nix/` | Starting points for new hosts |
| `just/`, `scripts/` | Bodies of the `just` recipes and helper scripts |

## Host composition

`flake.nix` lists every host in `hostConfigs` with its `system` and
`deviceType`. `mkHost` turns each entry into a NixOS configuration. Installation
images and the disposable build worker use separate construction paths.

A host's `default.nix` is import-focused and pins `system.stateVersion`.
Small composition settings may remain there. Shared profiles and roles come first, then
a blank line, then host-local modules, each group sorted alphabetically. Shared
modules do not branch on the hostname. They expose an option, and the host sets
it.

## Ownership boundaries

Use these boundaries for new code and incremental refactors. Existing files
do not all follow them yet.

| Responsibility | Owner |
| --- | --- |
| Reusable options and guarded implementation | `modules/` or `modules/home-manager/` |
| Opinionated service configuration, proxy and monitoring integration | `services/` |
| Optional capability or application bundle | `profiles/features/<area>/` |
| Deliberately universal policy | `profiles/base/` |
| Machine class or shared role composition | `profiles/specializations/` |
| Hardware support | `profiles/hardware/` |
| Host-specific values and exceptions | `hosts/<host>/` or the private input |
| Personal user configuration | `home-manager/` |

Here, `specializations` means roles, not NixOS `specialisation` boot variants.
Roles compose features and set policy; reusable service implementation should
not live inside a laptop or server role. Base can select reusable features when
they are deliberate policy for every full-baseline consumer; implementation
still belongs in the feature directory. Promote host-local collections only
when they represent a deliberate reusable capability.

Keep prerequisite imports with their consumer. For example, a backup profile
should import its backup service rather than depending on a workstation parent
to do so. Multiple consumers may legitimately import the same module path;
clear ownership matters more than eliminating every repeated import.

Import order affects the order of merged lists. Moving a prerequisite into
a child module can reorder packages, backup paths and generated units even
when the same files remain reachable. Preserve existing ordering during
mechanical moves; do not add override priorities merely to hide unexpected
differences. Keep a composition-level import when relocating it would change
the evaluated configuration, and document that dependency until a deliberate
behavior change is appropriate.

Prefer options beside their guarded implementation. Consolidate the existing
`modules/options/` split incrementally, retaining shared declarations where
NixOS and Home Manager both need them. Importing reusable definitions should
not enable unrelated services. Avoid wrappers that add no policy or useful
composition boundary.

## Refactoring validation

Separate mechanical moves from behavior changes. Record all consumers,
including exports used by the private input. Keep exports stable until their
consumers migrate. Public references alone cannot prove a file is unused.

On a remote worker, compare clean before/after evaluations for affected hosts,
including images. Compare system derivations, inspect differences with
`nix-diff`, and compare rendered configuration and secret source mappings for
touched services. Follow [AGENTS.md](../AGENTS.md) for formatting and linting.
Every existing capability must remain reachable after a mechanical move.

## Public and private split

This repository is public and holds no secrets. The private repository
`nixos-config-private` holds:

- SOPS files, including the host-specific ones and `.sops.yaml`
- OpenTofu configuration, with its `just` recipes
- Private modules and infrastructure records

The private repository is a normal flake input, pinned in `flake.lock`. Every
host gets a GitHub token for it through `access-tokens` in `nix.conf`. Public
modules reach secrets at runtime through `config.sops.secrets.*.path` or
`sops.templates`.

The private flake receives this flake's `nixosModules` as the `publicModules`
special argument. Removing or renaming such an export is a breaking change for
the pinned input.

To change both repositories, commit and push the private one first, then run
on a remote worker (never evaluate locally):

```sh
nix flake lock --update-input nixos-config-private
```

Copy the lock file back after checking for concurrent local changes, then
commit it as `bump my privates`.
