# Full-Nix Android host profiles

Experimental Linux/glibc Home Manager configurations for `zf10` and `p11`, for
the isolated TermuxPP full-Nix runtime. These are **not** native nixpp bundles,
NixOS systems, or nix-on-droid configurations. Both use `aarch64-linux` packages
and the runtime's persistent `/home/nix`.

The existing `hosts/*/default.nix`, native bundle outputs, SSH daemons and recovery
shells are unchanged. Only the host-owned prompt settings are imported from those
hosts: their native cache/SSH modules target a different activation mechanism.

## Build and check

Run on a disposable build worker, from this repository root with its pinned
private input available. Do not evaluate/build these on the workstation.

```sh
nix build --impure --expr '
  let f = builtins.getFlake (toString ./.);
      homes = import ./android/full-nix { inputs = f.inputs; };
  in homes.zf10.activationPackage' -o zf10-home

nix build --impure --expr '
  let f = builtins.getFlake (toString ./.);
      homes = import ./android/full-nix { inputs = f.inputs; };
  in homes.p11.activationPackage' -o p11-home

nix eval --impure --json --expr '
  import ./android/full-nix/tests.nix {
    inputs = (builtins.getFlake (toString ./.)).inputs;
  }'

nix develop --command nixfmt --check android/full-nix/*.nix
nix develop --command statix check android/full-nix
nix develop --command deadnix android/full-nix
```

The invariants check guest identity/home, host-specific colors, Linux package
architecture, an empty native APT dependency list and no systemd service startup.

## Included

- Shared portable Zsh settings and plugins, Atuin, direnv/nix-direnv, zoxide,
  vivid, bat, eza, fd and ripgrep.
- Host identity and prompt color. A usable fallback prompt works without an
  existing yadm checkout or `p10k.zsh`.
- Nix-managed Zsh and tmux, Git, Neovim, Python, rbw, SOPS, GnuPG, OpenSSH and
  standard shell tools.
- Home Manager generations, with no attempt to launch systemd user services.
- Lightweight fzf integration rather than the desktop image/video preview
  closure. This is an intentional mobile-specific composition choice.

## Activation boundary

The two generations have been built on a worker. Building them is not proof of
activation or Android acceptance. Do not switch the phone's native nixpp profile
or run these activation scripts in the native Android home.

Once the closure is available in the guest's virtual store, run its `activate`
script **inside** `session.sh --`, with guest `HOME=/home/nix`. Preserve the
previous Home Manager generation and any conflicting guest files first. Then
start `session.sh -- zsh -l` to test the managed shell before changing runtime
startup. The runtime currently defaults to Bash, not these Zsh profiles.

Large closures must be imported directly on the device from a signed cache or
built remotely; do not shuttle them through the workstation. The runtime must
already be qualified for the device's ABI and page size. In particular, the
current launcher accepts only AArch64/4096-byte-page devices; the tablet has not
been qualified by this configuration change.

## Deliberately not migrated

This is the declarative shell/package baseline, not complete feature parity:

- Native SSH host identities/daemon ports and read-only cache credentials remain
  owned by native recovery. No credentials are copied into the guest or Nix store.
- Android API/Tasker helpers, shared storage bindings and native command bridges
  need separate runtime integration; Linux binaries are not substitutes for the
  Bionic helpers.
- The existing native yadm home, local plugins, prompt file, history, private
  shell settings and editor configuration are not copied or overwritten. The
  guest gets packaged Neovim, not the native bundle's LazyVim configuration.
- Automatic startup, on-device Home Manager activation/rollback and full host
  acceptance remain deployment gates. Keep the native shell usable throughout.
