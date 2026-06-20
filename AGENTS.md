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

## Deployment
- Avoid committing or pushing changes from this environment unless the user explicitly asks.
- Prefer committing only verified, working changes.
- To deploy changes to a host, run `just deploy TARGET_HOST`.
  - Check `hostname` first: if the current machine is the target host, omit the argument (`just deploy`) to build and switch locally without SSH/rsync.
- To apply standalone Home Manager changes on fnuc (non-NixOS), run `just hm` (or `just hm <hostname>` for a specific host). This rsyncs the repo to `/nix/tmp/hm-builds/` first so uncommitted changes are included and Nix builds efficiently on the same filesystem.

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
- `profiles/` is the single composition point for everything. It contains both
  foundational layers (`profiles/global/`, `profiles/network/`) and higher-level
  bundles: machine-class directories (`profiles/server/`, `profiles/gui/`,
  `profiles/laptop/`, `profiles/work/`) and role aggregator files
  (`profiles/workstation.nix`, `profiles/tdarr-node.nix`, etc.). A role
  aggregator is a pure `imports` list with a one-line header comment, grouping
  imports shared by **2+ hosts**.
- Don't create a profile for a single-host stack — that is just indirection;
  keep those imports inline in the host's `default.nix`.
- Avoid host-specific conditionals in shared modules, profiles, or services.
  Do not branch on `config.networking.hostName`, expressions like
  `config.networking.hostName == "..."`, Home Manager `hostname`, or similar
  host facts inside shared module code when the behavior is only for one host.
- If shared code needs host-varying behavior, prefer adding a dedicated module
  option and setting it from the relevant host config instead of inspecting the
  host identity inside the shared module.
- Put host-specific overrides in the relevant `hosts/<host>/default.nix` or
  standalone Home Manager host entrypoint instead. Shared modules should expose
  reusable options/defaults, not embed per-host exceptions.

## NetBox
- When working on NetBox inventory or metadata tasks, consult [NETBOX.md](./NETBOX.md) first and follow its conventions.

## Home Assistant
- For authenticated Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.
- `zhj hass-cli` is the reliable path for service calls in this environment. Example:
  `zsh -lc 'zhj hass-cli service call light.turn_on --arguments entity_id=light.zha_hue_bedroom_light,brightness_pct=80,color_temp_kelvin=2518'`
- After editing Home Assistant YAML directly, reload the affected domain via `zhj hass::reload ...`.
- For automations, use `zsh -lc 'zhj hass::reload automation'`.
- Apply the same pattern to other HA domains after direct edits, for example scripts via `zsh -lc 'zhj hass::reload script'`.
