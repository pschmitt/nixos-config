<p align="center">
  <img src="assets/logo.svg" width="200" alt="A pyramid with a floating gold capstone holding an eye whose iris is a Nix snowflake, in front of a black hole">
</p>

<p align="center">
  <a href="https://nixbot.brkn.lol/repos/github/pschmitt/nixos-config"><img src="https://nixbot.brkn.lol/repos/github/pschmitt/nixos-config/badge.svg?branch=main" alt="nixbot"></a>
</p>

<h1 align="center">pschmitt's nixos book of horrors</h1>

<p align="center">
  One flake for all my machines: laptops, servers, Raspberry Pis and install
  media, with NixOS, Home Manager and the services they run.
</p>

This is a personal configuration, published to read and borrow from. It is not
a framework. Secrets and private infrastructure live in a separate private
repository, so the hosts only evaluate with access to that flake input.

## Features

- **Fleet in one flake**: x86_64, aarch64 and armv6l hosts, declared in
  [`flake.nix`](flake.nix) and composed from shared profiles. See
  [Architecture](docs/architecture.md).
- **Public and private split**: this repository holds no secrets. SOPS files,
  OpenTofu and private modules come from the `nixos-config-private` input.
- **Home Manager as a NixOS module**: one home config tree, fed with host facts
  through a bridge. See [home-manager/README.md](home-manager/README.md).
- **Desktop profiles** for Hyprland and GNOME under
  [`profiles/features/desktop`](profiles/features/desktop).
- **Self-hosted services** such as Immich, Nextcloud, Vaultwarden, Forgejo,
  Stalwart and a Home Assistant VM, as modules under [`services`](services).
- **Custom packages and overlays** under [`pkgs`](pkgs) and
  [`overlays`](overlays), kept current by a daily `nix-update` workflow. See
  [Packages](docs/packages.md).
- **Provisioning** with disko, nixos-anywhere, ISO images and Raspberry Pi SD
  images. See [Hosts](docs/hosts.md).
- **Self-hosted CI**: nixbot for x86_64, GitHub ARM runners for aarch64, and a
  binary cache for the results. See [CI](docs/ci.md).

## Install

You need Nix with flakes, [`just`](https://github.com/casey/just) and a GitHub
token that can read `nixos-config-private`.

```sh
git clone git@github.com:pschmitt/nixos-config.git
cd nixos-config
```

To reuse parts without the private input, copy the modules you need. The flake
exports `nixosModules`, `homeManagerModules`, `overlays` and `packages`.

## Quick start

```sh
just                                       # list all recipes
just repl HOST                             # open a Nix REPL for a host
just eval --host HOST networking.hostName  # read one option of a host
just deploy HOST                           # build on the target and switch
just nix-update --list                     # list the custom packages
just iso                                   # build the installer ISO
```

Continue with [Deployment](docs/deploy.md) to roll out a change, or with
[Hosts](docs/hosts.md) to add a machine.

## Documentation

| Topic | Description |
| --- | --- |
| [Architecture](docs/architecture.md) | Repository layout, host composition, public and private split |
| [Deployment](docs/deploy.md) | Switching hosts, automatic upgrades, known false failures |
| [Hosts](docs/hosts.md) | Adding, installing and removing a host |
| [Packages](docs/packages.md) | Updating the custom packages |
| [CI](docs/ci.md) | nixbot, GitHub workflows and the binary cache |
| [home-manager/README.md](home-manager/README.md) | Home Manager layout and module conventions |
| [services/harmonia/README.md](services/harmonia/README.md) | CI cache delivery and the LAN mirror |
| [services/http-static/README.md](services/http-static/README.md) | Blob archive listing |
| [android/nixpp/README.md](android/nixpp/README.md) | Termux client for reference-free Nix outputs |
| [android/termux-native/README.md](android/termux-native/README.md) | Native Termux environments built with Nix |
| [AGENTS.md](AGENTS.md) | Code style, service conventions and rules for AI agents |

## License

[GPL-3.0-only](LICENSE).
