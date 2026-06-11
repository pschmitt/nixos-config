# Home Manager Layout

There is **one** shared home config tree. It is `osConfig`-free: modules read
host facts from `config.*` / `config.host.*` / `config.mainUser` /
`config.domains` / the `hostname` specialArg — never `osConfig`. The only
difference between the two ways HM runs is *where those facts come from*.

## Entrypoints

- `default.nix`
  NixOS integration entrypoint (imported from NixOS hosts via the flake). It
  imports `home.nix` and acts as the **bridge**: it copies host facts from the
  NixOS `config` into the home config (`mainUser`, `domains`, `host.*`) and
  passes import-gating facts (`guiEnable`, `bluetoothEnable`) via
  `extraSpecialArgs`.

- `home.nix`
  The single shared root, used by both NixOS-backed and standalone hosts. Imports
  `base.nix`, `sops.nix`, `ssh.nix`, `work`, `yadm.nix`, and conditionally `gui`
  / `bluetooth.nix` (gated on the `guiEnable` / `bluetoothEnable` specialArgs).

- `base.nix`
  Shared base profile. Also imports the option modules that provide the facts:
  `../modules/main-user.nix`, `../modules/domains.nix`, and `./host.nix`.

- `host.nix`
  Declares `config.host.*` — the host facts the home config needs (sopsFile,
  highDpi, iioSensor, provisionSshKeys, stateVersion, …). Defaults make a
  headless standalone host work out of the box.

## Host facts: integrated vs standalone

- **NixOS-backed** (ge2, gk4, x13, lrz): the bridge in `default.nix` derives
  every fact from the NixOS `config`. Activated automatically by `nixos-rebuild`
  (`just deploy`).
- **Standalone** (fnuc, non-NixOS): the host module sets the facts explicitly
  (`host.sopsFile`, `host.stateVersion`, …) and the flake's `mkHome` passes
  `guiEnable` / `bluetoothEnable` (default `false`).

## Conventions for new modules

- Read facts from `config.host.*` / `config.mainUser` / `config.domains` or the
  `hostname` specialArg. **Do not** read `osConfig`.
- If a fact must gate an `import` (not just config), pass it as a specialArg
  (like `guiEnable`) — referencing `config` in `imports` causes an infinite
  recursion.
- Add a new fact to `host.nix` (+ set it in the bridge and for standalone hosts)
  rather than reaching into system state.
