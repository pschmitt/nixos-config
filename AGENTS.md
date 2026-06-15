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

## NetBox
- When working on NetBox inventory or metadata tasks, consult [NETBOX.md](./NETBOX.md) first and follow its conventions.

## Home Assistant
- For authenticated Home Assistant CLI access from this repo, prefer `zsh -lc 'zhj hass-cli ...'`.
- `zhj hass-cli` is the reliable path for service calls in this environment. Example:
  `zsh -lc 'zhj hass-cli service call light.turn_on --arguments entity_id=light.zha_hue_bedroom_light,brightness_pct=80,color_temp_kelvin=2518'`
- After editing Home Assistant YAML directly, reload the affected domain via `zhj hass::reload ...`.
- For automations, use `zsh -lc 'zhj hass::reload automation'`.
- Apply the same pattern to other HA domains after direct edits, for example scripts via `zsh -lc 'zhj hass::reload script'`.
