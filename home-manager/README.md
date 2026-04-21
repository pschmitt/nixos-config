# Home Manager Layout

This directory has a small number of entrypoints:

- `default.nix`
  NixOS integration entrypoint. This is the module imported from NixOS hosts.

- `base.nix`
  Shared Home Manager base profile. This is the common module stack used by both
  NixOS-backed Home Manager and standalone Home Manager hosts.

- `home.nix`
  NixOS-specific Home Manager profile. This extends `base.nix` with modules that
  depend on NixOS state such as `sops.nix`, `ssh.nix`, `work`, `yadm.nix`, and
  GUI/Bluetooth conditionals derived from `osConfig`.

Standalone hosts should import `base.nix` directly from their host entrypoint
under `hosts/<name>/default.nix`, and then add any standalone-only modules such
as `sops-standalone.nix`.
