# Home Manager Layout

There is **one** shared home config tree, used as a NixOS submodule. It is
`osConfig`-free: modules read host facts from `config.*` / `config.host.*` /
`config.mainUser` / `config.domains` / the `hostname` specialArg — never
`osConfig`.

Termux bundles are separate: `pkgs/termux/native/mkTermuxBundle.nix` builds a
standalone profile from `modules/home-manager/termux.nix`, without `home.nix`.

## Entrypoints

- `default.nix`
  NixOS integration entrypoint (imported from NixOS hosts via the flake). It
  imports `home.nix` and acts as the **bridge**: it copies host facts from the
  NixOS `config` into the home config (`mainUser`, `domains`, `host.*`) and
  passes import-gating facts (`guiEnable`, `bluetoothEnable`) via
  `extraSpecialArgs`.

- `home.nix`
  The single shared root. Imports `base.nix`, `sops.nix`, `ssh.nix`,
  `ssh-clipboard.nix`, `work`, `yadm.nix`, and conditionally `gui` /
  `bluetooth.nix` (gated on the `guiEnable` / `bluetoothEnable` specialArgs).

- `base.nix`
  Shared base profile. Also imports the option modules that provide the facts,
  such as `../modules/main-user.nix`, `../modules/domains.nix` and `./host.nix`.

- `host.nix`
  Declares `config.host.*` — the host facts the home config needs (sopsFile,
  highDpi, iioSensor, provisionSshKeys, stateVersion, …).

## Host facts

The bridge in `default.nix` derives every fact from the NixOS `config`.
`nixos-rebuild` activates the home config with the system (`just deploy`).

## Directories

- `cli/`: shells, editors and terminal tools
- `devel/`: development tooling, AI agents and their skills
- `gui/`: desktop applications, imported only with `guiEnable`
- `services/`: user services
- `work/`: work-specific configuration
- `scripts/`: scripts wrapped into the profile

## Conventions for new modules

- Read facts from `config.host.*` / `config.mainUser` / `config.domains` or the
  `hostname` specialArg. **Do not** read `osConfig`.
- If a fact must gate an `import` (not just config), pass it as a specialArg
  (like `guiEnable`) — referencing `config` in `imports` causes an infinite
  recursion.
- Add a new fact to `host.nix` (+ set it in the bridge) rather than reaching
  into system state.
