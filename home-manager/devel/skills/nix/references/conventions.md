# Nix Conventions

## Repository Structure

- `hosts/`: Per-host NixOS configurations.
- `modules/`: Shared NixOS modules and custom option definitions.
- `modules/home-manager/`: Shared Home Manager modules.
- `home-manager/`: User-level Home Manager configurations.
- `common/`: Shared base *platform layers* — the machine class/capability a host
  *is* (`global`, `server`, `gui`, `laptop`, `network`, `work`), imported
  explicitly and forming a transitive hierarchy.
- `profiles/`: Reusable host *roles* — groupings of service imports shared
  by more than one host (see "Host composition" below).
- `pkgs/`: Custom package definitions.
- `overlays/`: Nixpkgs overlays.
- `hardware/`: Hardware-specific configuration snippets.

Custom options are defined under `modules/` (`custom.nix`, `sops.nix`,
`domains.nix`, `hardware.nix`, `main-user.nix`, `syncthing.nix`) and wired up via
`modules/default.nix` — add new option modules to that import list.

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

- Config: `.sops.yaml`; secrets dir: `secrets/`; tool: `sops`. Never print
  decrypted secrets to the console or logs.
- The **default** sops file is `secrets/shared.sops.yaml` (set in
  `common/global/sops.nix` as `sops.defaultSopsFile`).
- For a secret that lives in the **host-specific** file (`custom.sopsFile`), use the
  helper from `modules/sops.nix` instead of repeating `inherit (config.custom) sopsFile;`:

  ```nix
  sops.secrets."foo/bar" = config.custom.mkSecret { };
  sops.secrets."foo/baz" = config.custom.mkSecret { owner = "svc"; };
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

- Hosts import `common/<category>` snippets plus the services they run.
- When **two or more hosts share a service grouping**, extract it into
  `profiles/<role>.nix` (top-level) and have those hosts import the profile (e.g.
  `profiles/tdarr-node.nix` shared by rofl-13/rofl-14, `profiles/workstation.nix`
  shared by ge2/gk4/x13). A profile is a pure `imports` aggregator with a
  one-line header comment. Don't create a profile for a single-host stack — that
  is just indirection.

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
