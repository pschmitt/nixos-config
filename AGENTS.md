# Repository Guidelines

## Environment preparation
- Before invoking the `nix` CLI inside this repository, run `source /etc/profile.d/nix.sh` **only when working in the cloud environment**. Do not source it when running from the Codex CLI or GitHub Copilot context.
- After sourcing (cloud only), verify the installation with `nix --version` if needed.
- When suggesting commands that use a flake selector, always single-quote the selector. Example: use `'.#fnuc'`, not `.#fnuc`.
- To decrypt SOPS files in this repo from Codex/CLI contexts that do not have `~/.config/sops/age/keys.txt`, export an age key derived from the main SSH key first:
  `export SOPS_AGE_KEY="$(ssh-to-age --private-key -i ~/.ssh/id_ed25519)"`
- Prefer updating SOPS values with `sops set`. Example:
  `sops set ~/git/svc/sops/example.yaml '["app2"]["key"]' '"app2keystringvalue"'`
- After any SOPS change, always verify the diff by decrypting the previous version and the new version, then diffing the plaintexts.
- Default to SOPS for anything that even remotely smells like a secret or an identifier — not just passwords/tokens/keys, but also things like TLS/SSH fingerprints, device serials, account IDs, or other values that authorize access or identify a specific person/device. When in doubt, treat it as SOPS-worthy rather than committing it in cleartext to a tracked Nix file (it would otherwise land in the world-readable Nix store). Inject such values at activation/runtime (e.g. `sops.templates` referencing `config.sops.placeholder.*`, or `config.sops.secrets.*.path`) rather than baking them into generated config via `pkgs.formats.*` at eval time.

## Deployment
- Prefer committing only verified, working changes.
- After making changes, deploy to the target systems:
  - **Before committing** (e.g. to test local or uncommitted changes): run `just deploy TARGET_HOST` (or omit the argument with `just deploy` if currently on the target host to build and switch locally without SSH/rsync).
  - **If already committed**: deploy by SSH'ing to the target host and restarting `nixos-upgrade.service` (`systemctl restart nixos-upgrade.service`).
- fnuc has been migrated to full NixOS (see `hosts/fnuc/default.nix`); deploy it like any other NixOS host with `just deploy` (see above), which also switches its embedded `home-manager.users.pschmitt` module. It is no longer a standalone Home Manager host.
- `just hm` (or `just hm <hostname>`) applies a *standalone* Home Manager `homeConfigurations.<hostname>` profile for a non-NixOS host, rsyncing the repo to `/nix/tmp/hm-builds/` first so uncommitted changes are included and Nix builds efficiently on the same filesystem. There is currently no such host in this flake — `homeConfigurations.fnuc` predates fnuc's NixOS migration and is stale/unused; do not point users at it.
- **Deployment gotchas**:
  - `just deploy <host>` can report failure even when the switch actually succeeded if NetworkManager restarts during activation and terminates the SSH session (`Timeout, server <host> not responding`). The remote `nixos-rebuild switch` process continues running to completion. When this happens, re-`ssh` and verify `readlink -f /run/current-system`, check generations (`nix-env -p /nix/var/nix/profiles/system --list-generations | tail -3`), and confirm units are active.
  - Hosts with `services/initrd-luks-ssh-unlock.nix` present a distinct SSH host key while in initrd waiting for LUKS unlock (`/etc/ssh/initrd/ssh_host_{ed25519,rsa}_key`). A changed host key warning during the boot/unlock window is expected.
- **Verifying refactors are behavior-preserving**:
  - Compare secrets evaluation: `nix eval .#nixosConfigurations.<host>.config.sops.secrets --apply 's: builtins.mapAttrs (n: v: toString v.sopsFile) s' --json` and diff.
  - Compare full system: compare `config.system.build.toplevel.drvPath`. Use `nix-diff <before.drv> <after.drv>` to confirm differences are limited to flake input hashes (`etc`, `etc-profile`, `etc-nix-registry.json`) and not systemd units, packages, or services.

## Private configuration repository
- **Never put a secret in this repository, full stop.** Treat this public
  repository as safe to publish, and treat that as a hard constraint, not a
  goal to balance against convenience. All secrets and sensitive material
  must live in `pschmitt/nixos-config-private`, never in tracked files here.
  This includes private SOPS ciphertext, credentials, passwords, tokens, private
  keys, SSH/TLS fingerprints and host keys, device serials, account IDs,
  inventory/provider credentials, private infrastructure records, and
  secret-bearing helper or provisioning scripts. If you are unsure whether
  something belongs here, it doesn't — put it in the private repo instead.
- Keep only public interfaces, non-sensitive defaults, and references in this
  repository. Private modules, secrets, and infrastructure config live in the
  private repository instead; this repository contains only references to
  them through the private flake input. See that repository's own
  `AGENTS.md` for its internal layout (host/secrets structure, SOPS
  conventions, etc.) — don't duplicate that detail here.
- The flake references `nixos-config-private` as
  `github:pschmitt/nixos-config-private`, a normal flake input pinned in
  `flake.lock`; it follows the top-level `nixpkgs`. Fetching it requires a
  GitHub token. Every host gets one through `access-tokens` in `nix.conf`
  (system-level via `profiles/base/nix/secrets.nix`, user-level via
  `home-manager/devel/nix.nix`). Do not remove that plumbing or replace the
  GitHub input with `path:./private`.
- Edit the private repository through its separate local checkout when needed.
  Set `PRIVATE_CONFIG_DIR` for scripts here that need it. Commit and publish
  changes there first; then update this repository's lock file with
  `nix flake lock --update-input nixos-config-private`. Always use the commit
  message `bump my privates` for that lock-file commit.
- The canonical SOPS configuration is `nixos-config-private/.sops.yaml`.
  Scripts use it for both public host ciphertext and private-repository secrets;
  do not recreate a public `.sops.yaml`.
- The default SOPS file is `secrets/nixos-shared.sops.yaml` in the private
  configuration checkout (set from the private flake input as `sops.defaultSopsFile`).
- For secrets in the host-specific file (`sops.hostSopsFile`), use the helper from
  `modules/sops.nix` rather than repeating `sopsFile`:
  ```nix
  sops.secrets."foo/bar" = config.sops.mkHostSecret { };
  sops.secrets."foo/baz" = config.sops.mkHostSecret { owner = "svc"; };
  ```
- Never add a secret or sensitive identifier here merely because it is
  encrypted, obfuscated, or needed by a script. If a public module needs one,
  expose a runtime or activation interface and source the value from the
  private input, SOPS, or a host/runtime secret path.

## Repository layout
- `hosts/`: Per-host NixOS configurations (`hosts/<hostname>/default.nix`).
- `modules/`: Shared NixOS modules and custom option definitions.
- `modules/home-manager/`: Shared Home Manager modules.
- `home-manager/`: User-level Home Manager configurations.
- `profiles/base/`: Common machine baseline.
- `profiles/features/`: Optional capabilities (e.g. `network/`, `desktop/`, `work/`).
- `profiles/specializations/`: Machine classes and reusable host roles.
- `services/`: Service modules, including reusable Home Manager user services.
- `pkgs/`: Custom package definitions.
- `overlays/`: Nixpkgs overlays.
- `hardware/`: Hardware-specific configuration snippets.

## Code Style
- Nix code changes should be formatted correctly with `nixfmt`.
- `statix` checks should pass. After Nix code changes, run `statix check` from within `nix develop`.
- Also run `deadnix` to catch unused arguments or bindings. Drop genuinely unused args; `_`-prefix intentionally-unused lambda args (`_name: fs: ...`). Leave idiomatic `final: prev:` / `finalAttrs:` as-is.
- Tofu code changes should be formatted with `tofu fmt`.
- **Never** write code with trailing whitespace.
- Don't use `with lib;`. Qualify explicitly (`lib.mkOption`, `lib.types.str`, `lib.mkIf`) — that is the repo-wide style. For many uses in one scope, prefer `inherit (lib) mkOption mkIf types;` over `with`. This applies to package `meta` blocks too (`meta = { license = lib.licenses.mit; ... }`, and `maintainers = with lib.maintainers; [ pschmitt ];`).
- New files must be staged with `git add` (e.g. `git add -N <file>`) before they are visible to flake evaluation.
- Build structured configuration with `pkgs.formats.{yaml,toml,json,ini}` and an attrset, not hand-concatenated strings. Example: `(pkgs.formats.yaml { }).generate "x.yaml" { ... }`.
- Shell scripts in Nix:
  - Follow the `shell` skill for script bodies.
  - Non-trivial scripts (branching/loops): put the body in a sibling `scripts/<name>.sh` and wrap it with `pkgs.writeShellApplication` with appropriate `runtimeInputs`. The wrapper provides `set -euo pipefail` and build-time shellcheck.
  - Avoid `writeShellScriptBin` for non-trivial scripts.
  - In Home Manager, wrap repo scripts into the profile with shared helpers in `modules/home-manager/script-lib.nix` (`wrapScript` / `wrapDir` / `toFiles`).

## Option naming
- Put options in the namespace that owns their behavior: use native namespaces
  such as `services.*`, `programs.*`, `hardware.*`, `domains.*`, and `system.*`.
- Do not introduce a `custom.*` namespace. Keep repo-owned `dotfiles.*` options
  lean and mean, reserving them for cross-layer or user-facing configuration
  that has no more specific native namespace.
- For features shared between NixOS and Home Manager, declare reusable options
  in shared modules imported by both contexts and bridge system values explicitly
  in `home-manager/default.nix`.
- For machine capabilities, use canonical facts under `hardware.*` and bridge
  them into Home Manager rather than introducing ad hoc host flags.
- Before adding a host fact under `home-manager/host.nix`, check whether it
  should instead be a NixOS-side option in `modules/`.

## Host composition
- `profiles/base/` is the common baseline. Optional capabilities live under
  `profiles/features/` (for example `network/`, `desktop/`, and `work/`), while
  machine classes and reusable host roles live under
  `profiles/specializations/` (for example `server/`, `laptop/`,
  `workstation/`, and `homelab-server/`).
- Keep every NixOS host's `hosts/<host>/default.nix` as its concise composition
  entrypoint. Avoid special-case entrypoint names such as `nixos.nix`; point the
  flake at the host directory or its `default.nix`.
- In a host `default.nix`, list shared profiles/features/roles first, then a
  blank line, then host-local modules. Sort imports alphabetically within each
  group. Keep this grouping consistent when adding imports.
- Keep Nix files focused on one capability or responsibility. Split host
  configuration into small, cohesive modules when that makes ownership clearer;
  do not scatter settings into arbitrary files or create modules that only add
  indirection. Keep each host `default.nix` import-focused and put related imports
  inside the module that owns that capability where practical (for example, an
  initrd Wi-Fi module should import its initrd SSH-unlock service).
- When reorganizing host modules, preserve the evaluated configuration: do not
  accidentally enable, disable, omit, or unprovision services. Verify that
  extracted settings and imports remain reachable from the host entrypoint. Keep
  module contents and service configuration unchanged when reorganizing imports;
  never omit an existing service just to shorten an import list.
- Don't create a specialization for a single-host stack unless it is a
  deliberate reusable concept; shared service groupings are appropriate when
  used by **2+ hosts**.
- Avoid host-specific conditionals in shared modules, profiles, or services.
  Do not branch on `config.networking.hostName`, expressions like
  `config.networking.hostName == "..."`, Home Manager `hostname`, or similar
  host facts inside shared module code when the behavior is only for one host.
- If shared code needs host-varying behavior, prefer adding a dedicated module
  option and setting it from the relevant host config instead of inspecting the
  host identity inside the shared module.
- Put host-specific overrides in a host-local module imported by
  `hosts/<host>/default.nix` (or the standalone Home Manager entrypoint).
  Shared modules should expose reusable options/defaults, not embed per-host
  exceptions.

## Home Manager
- There is one shared home config tree, used as a NixOS submodule. It is `osConfig`-free:
  modules read host facts from `config.host.*`, `config.mainUser`,
  `config.domains`, or the `hostname` specialArg — never `osConfig`.
- Host facts (`config.host.*`, declared in `home-manager/host.nix`) are fed by
  the bridge in `home-manager/default.nix` (integrated, from the NixOS `config`).
  Add new facts there rather than reaching into system state.
- A fact that gates an `import` (not just config) must be a `specialArg` (e.g.
  `guiEnable`, `bluetoothEnable`) — referencing `config` in `imports` causes an
  infinite recursion. See `home-manager/README.md`.

## NetBox
- When working on NetBox inventory or metadata tasks, consult [NETBOX.md](./NETBOX.md) first and follow its conventions.

## Home Assistant
- For authenticated Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.
- `zhj hass-cli` is the reliable path for service calls in this environment. Example:
  `zsh -lc 'zhj hass-cli service call light.turn_on --arguments entity_id=light.zha_hue_bedroom_light,brightness_pct=80,color_temp_kelvin=2518'`
- After editing Home Assistant YAML directly, reload the affected domain via `zhj hass::reload ...`.
- For automations, use `zsh -lc 'zhj hass::reload automation'`.
- Apply the same pattern to other HA domains after direct edits, for example scripts via `zsh -lc 'zhj hass::reload script'`.
