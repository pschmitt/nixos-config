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
- Avoid committing or pushing changes from this environment unless the user explicitly asks.
- Prefer committing only verified, working changes.
- To deploy changes to a host, run `just deploy TARGET_HOST`.
  - Check `hostname` first: if the current machine is the target host, omit the argument (`just deploy`) to build and switch locally without SSH/rsync.
- fnuc has been migrated to full NixOS (see `hosts/fnuc/default.nix`); deploy it like any other NixOS host with `just deploy` (see above), which also switches its embedded `home-manager.users.pschmitt` module. It is no longer a standalone Home Manager host.
- `just hm` (or `just hm <hostname>`) applies a *standalone* Home Manager `homeConfigurations.<hostname>` profile for a non-NixOS host, rsyncing the repo to `/nix/tmp/hm-builds/` first so uncommitted changes are included and Nix builds efficiently on the same filesystem. There is currently no such host in this flake — `homeConfigurations.fnuc` predates fnuc's NixOS migration and is stale/unused; do not point users at it.

## Private configuration repository
- Treat this public repository as safe to publish. All secrets and sensitive
  material must live in `pschmitt/nixos-config-private`, never in tracked files
  here. This includes private SOPS ciphertext, credentials, passwords, tokens, private
  keys, SSH/TLS fingerprints and host keys, device serials, account IDs,
  inventory/provider credentials, private infrastructure records, and
  secret-bearing helper or provisioning scripts.
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
- Never add a secret or sensitive identifier here merely because it is
  encrypted, obfuscated, or needed by a script. If a public module needs one,
  expose a runtime or activation interface and source the value from the
  private input, SOPS, or a host/runtime secret path.

## Code Style
- Nix code changes should be formatted correctly with `nixfmt`.
- `statix` checks should pass.
- After Nix code changes, run `statix check` from within `nix develop`.
- Tofu code changes should be formatted with `tofu fmt`.
- **Never** write code with trailing whitespace.

## Option naming
- Prefer repo-owned option namespaces over generic top-level names.
- For cross-layer features shared between NixOS and Home Manager, use
  `custom.<domain>.*` or `custom.<domain>.<feature>.*` rather than bare names
  like `theme.*` or `browser.*`.
- For desktop/user-facing shared features, prefer `custom.desktop.*`.
- For actual machine capabilities, prefer canonical hardware facts under
  `hardware.*` and bridge them into Home Manager, rather than introducing
  ad hoc Home Manager-only host flags.
- Before adding a new host fact under `home-manager/host.nix`, check whether it
  should really be a NixOS-side option in `modules/` first.

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

## NetBox
- When working on NetBox inventory or metadata tasks, consult [NETBOX.md](./NETBOX.md) first and follow its conventions.

## Home Assistant
- For authenticated Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.
- `zhj hass-cli` is the reliable path for service calls in this environment. Example:
  `zsh -lc 'zhj hass-cli service call light.turn_on --arguments entity_id=light.zha_hue_bedroom_light,brightness_pct=80,color_temp_kelvin=2518'`
- After editing Home Assistant YAML directly, reload the affected domain via `zhj hass::reload ...`.
- For automations, use `zsh -lc 'zhj hass::reload automation'`.
- Apply the same pattern to other HA domains after direct edits, for example scripts via `zsh -lc 'zhj hass::reload script'`.
