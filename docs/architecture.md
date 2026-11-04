# Architecture

## Repository layout

| Path | Contents |
| --- | --- |
| `flake.nix` | Inputs, the host list and all flake outputs |
| `hosts/<host>/` | One directory per host, with `default.nix` as its entrypoint |
| `profiles/base/` | Baseline of every machine |
| `profiles/features/` | Optional capabilities: `desktop`, `diagnostics`, `network`, `work` |
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
`deviceType`. `mkHost` turns each entry into a NixOS configuration.

A host's `default.nix` only imports. Shared profiles and roles come first, then
a blank line, then host-local modules, each group sorted alphabetically. Shared
modules do not branch on the hostname. They expose an option, and the host sets
it.

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

To change both repositories, commit and push the private one first, then run:

```sh
nix flake lock --update-input nixos-config-private
```
