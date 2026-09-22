# Nix Conventions

## Repository Structure

- `hosts/`: Per-host NixOS configurations.
- `modules/`: Shared NixOS modules and custom option definitions.
- `modules/home-manager/`: Shared Home Manager modules.
- `home-manager/`: User-level Home Manager configurations.
- `profiles/base/`: The common machine baseline.
- `profiles/features/`: Optional capabilities such as networking, desktop, and
  work tooling.
- `profiles/specializations/`: Machine classes and reusable host roles.
- `services/`: Service modules, including reusable Home Manager user services.
- `pkgs/`: Custom package definitions.
- `overlays/`: Nixpkgs overlays.
- `hardware/`: Hardware-specific configuration snippets.

Declare options alongside the feature that owns them, using native option
namespaces such as `services.*`, `programs.*`, `hardware.*`, `domains.*`, or
`system.*`. Use `dotfiles.*` only for repo-owned cross-layer or user-facing
settings without a more specific native namespace. Do not add `custom.*` options.
Import NixOS modules through `modules/default.nix`; shared options consumed by
both NixOS and Home Manager must be declared in modules imported by both contexts.

## Code style (do / don't)

- **Format & lint:** `nixfmt` must pass; `statix check` (from `nix develop`) must
  pass; never leave trailing whitespace. These are enforced by pre-commit.
- **Also run `deadnix`** — it is *not* in pre-commit, so unused arguments/bindings
  slip through. Drop genuinely unused args; `_`-prefix intentionally-unused lambda
  args (`_name: fs: ...`). Leave idiomatic `final: prev:` / `finalAttrs:` as-is.
- **Don't use `with lib;`.** Qualify explicitly (`lib.mkOption`, `lib.types.str`,
  `lib.mkIf`) — that is the repo-wide style. For many uses in one scope, prefer
  `inherit (lib) mkOption mkIf types;` over `with`. This applies to package
  `meta` blocks too (`meta = { license = lib.licenses.mit; ... }`, and
  `maintainers = with lib.maintainers; [ pschmitt ];`).
- **New files must be `git add`-ed** before they are visible to the flake (flakes
  only read git-tracked files). `git add -N <file>` is enough for evaluation.

## Secrets (SOPS)

- Config: `.sops.yaml` in the private configuration checkout; host-specific and
  shared encrypted data lives in the private flake's `hosts/` and `secrets/`
  directories; tool: `sops`. Never print
  decrypted secrets to the console or logs.
- The **default** sops file is `secrets/nixos-shared.sops.yaml` in the private
  configuration checkout (set from the private flake input as
  `sops.defaultSopsFile`).
- For a secret that lives in the **host-specific** file (`sops.hostSopsFile`), use
  the helper from `modules/sops.nix` rather than repeating `sopsFile`:

  ```nix
  sops.secrets."foo/bar" = config.sops.mkHostSecret { };
  sops.secrets."foo/baz" = config.sops.mkHostSecret { owner = "svc"; };
  ```

- After any SOPS change, verify by decrypting the old and new versions and diffing
  the plaintext (see AGENTS.md).

## Shell scripts in Nix

- Follow the `shell` skill for the script body.
- **Non-trivial scripts** (anything with branching/loops): put the body in a sibling
  `scripts/<name>.sh` and wrap it with `writeShellApplication`:

  ```nix
  pkgs.writeShellApplication {
    name = "foo";
    runtimeInputs = [ pkgs.coreutils pkgs.jq ];
    text = builtins.readFile ./scripts/foo.sh;
  }
  ```

  The wrapper provides the shebang, `set -euo pipefail` and PATH (from
  `runtimeInputs`), and runs `shellcheck` at build time — so the body file omits the
  shebang/`set`/manual PATH. `set -u` means unset positional params must be guarded
  (`"${1:-}"`).
- **Avoid `writeShellScriptBin`** for non-trivial scripts (no shellcheck, no
  `set -euo pipefail`). Trivial one-line wrappers may stay inline.
- In Home Manager, wrap repo scripts into the profile with the shared helpers in
  `modules/home-manager/script-lib.nix` (`wrapScript` / `wrapDir` / `toFiles`) —
  don't reimplement per module.

## Generated config files

- Build structured config with `pkgs.formats.{yaml,toml,json,ini}` and an attrset,
  not hand-concatenated strings. Example: `(pkgs.formats.yaml { }).generate "x.yaml" { ... }`.

## Host composition

- Compose hosts from `profiles/base/`, relevant `profiles/features/`,
  `profiles/specializations/`, and host-local modules. Keep each `default.nix`
  focused on a readable import list rather than large module bodies.
- Reusable multi-host compositions belong under
  `profiles/specializations/<name>/`; for example, `tdarr-node/` is shared by
  rofl-13/rofl-14 and `workstation/` by ge2/gk4/x13. Avoid one-host-only
  aggregators that add indirection without expressing a reusable concept.

## Home Manager

- There is **one** shared home config tree, used as a NixOS submodule (fnuc/ge2/gk4/lrz/x13). It is **`osConfig`-free**:
  modules read host facts from `config.host.*`, `config.mainUser`,
  `config.domains`, or the `hostname` specialArg — never `osConfig`.
- Host facts (`config.host.*`, declared in `home-manager/host.nix`) are fed by
  the bridge in `home-manager/default.nix` (integrated, from the NixOS `config`)
  A future standalone configuration can set facts explicitly. Add new facts there rather
  than reaching into system state.
- A fact that gates an **`import`** (not just config) must be a specialArg (e.g.
  `guiEnable`, `bluetoothEnable`) — referencing `config` in `imports` causes an
  infinite recursion. See `home-manager/README.md`.

## Deployment gotchas

- **`just deploy <host>` can report failure even when the switch actually
  succeeded.** Hosts running a desktop (NetworkManager) restart it during
  activation if networking-related config changed; that kills the SSH session
  `just deploy` is running the remote `nixos-rebuild switch` over, producing
  `Timeout, server <host> not responding` and a non-zero exit — but the
  remote `nixos-rebuild switch` process itself keeps running to completion
  since it isn't killed by the dropped SSH session. **Don't trust the exit
  code alone on failure.** Re-`ssh` in (it comes back once NetworkManager is
  back up) and check `readlink -f /run/current-system` plus
  `nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3` to
  see whether the new generation is actually current, and spot-check that
  units stopped during activation (NetworkManager, docker, polkit, etc.) came
  back `active`.
- **Hosts with `services/initrd-luks-ssh-unlock.nix` (rofl-13, rofl-14, gk4,
  ge2, ...) present a *different* SSH host key while sitting in initrd
  waiting for the LUKS-unlock SSH connection**, from separate keys at
  `/etc/ssh/initrd/ssh_host_{ed25519,rsa}_key` — not the normal system's
  `/etc/ssh/ssh_host_*`. If a host was just rebooted and SSH suddenly reports
  `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`, that's expected during
  the initrd window, not necessarily a compromised host — the real system
  key reappears once it boots past LUKS unlock into the full system. Still
  worth a quick sanity check (e.g. confirm the reboot was expected) before
  writing it off, but don't treat it as a hard security incident on its own.

## Verifying refactors are behaviour-preserving

Refactors should not change what gets deployed. Prove it by eval-diffing the
relevant config before/after:

- Secrets: `nix eval .#nixosConfigurations.<h>.config.sops.secrets --apply 's: builtins.mapAttrs (n: v: toString v.sopsFile) s' --json` and diff.
- Whole system: compare `config.system.build.toplevel.drvPath`. NOTE: adding/removing
  any tracked file changes the flake `self` source hash, which propagates into
  `/etc/nix/registry.json` and `/etc/nixos` — so the drvPath *will* differ after
  adding files. Use `nix-diff <before.drv> <after.drv>` to confirm the only
  differences are that source-hash noise (`etc`, `etc-profile`, `etc-pam-environment`,
  `etc-nix-registry.json`) and not systemd units / packages / service config.
