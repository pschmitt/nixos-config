---
name: ha
description: Use when working with the Home Assistant configuration for the `hv` VM, especially for YAML config changes, `config.d/` edits, MCP-backed inspection or control, hass-cli inspection, API calls, Lovelace dashboard editing (`.storage/lovelace.*`), and validation before or after changes. Read `AGENTS.md` in the repo before editing.
---

# Home Assistant

Use this skill for Home Assistant configuration and inspection work on the `hv` VM.

## Hermes Agent

For live inspection and control, use the configured `home-assistant` MCP server
or the native Home Assistant channel. Hermes does not have `zhj` or local HA
tokens, and `/mnt/ha` may be unavailable because it is an SSHFS mount. Do not
make Hermes startup depend on that mount.

For configuration-file or Lovelace edits, use this fallback order:

1. Check `/mnt/ha` with bounded commands. If it is mounted and responsive,
   read `/mnt/ha/AGENTS.md` and work there.
2. If the mount is absent or stale, try `timeout 30 sudo -n
   hermes-mount-ha`, then re-check the mount with bounded commands. This is a
   narrowly scoped helper that starts only the HA mount unit; do not use broad
   `sudo`, `mount`, or `systemctl` commands.
3. If the mount still cannot be established, work directly on the HA server
   over the configured SSH route (for example through the Home Assistant MCP's
   SSH command capability) under `/homeassistant`, after reading its
   `AGENTS.md`. If that SSH route is unavailable too, report the access failure
   and ask the user to make the repository available.

Never assume an unresponsive `/mnt/ha` is usable: wrap probes such as `stat`,
`findmnt`, and file reads in a timeout.

## Repository

The HA config repo is mounted at `/mnt/ha` (SSHFS). Read `AGENTS.md` there for all access details, working conventions, and Lovelace editing procedures.

## Lovelace / Dashboard Editing

Dashboards in storage mode live at `/mnt/ha/.storage/lovelace.<url-slug>` (underscores, e.g. `lovelace.main_dashboard`).

**Writing the file on disk does NOT update HA's in-memory cache.** After any manual `.storage/` edit, push it live with `just push-dashboard <url-slug>` (run in `/mnt/ha`).

- **Mi-casa** (`lovelace.mi_casa`) is generated — edit `dashboards/casa/build.py` and run `just build-casa`, never edit the storage file directly.
- **Other dashboards** — parse with `json`, mutate, write back, then `just push-dashboard <url-slug>`. See `/mnt/ha/AGENTS.md` § *Lovelace / Dashboard Editing*.
- For raw API or `hass-cli` access use the dedicated AI Agent user: rbw entry `Home Assistant (AI Agent)`, field `Long-Lived Access Token` (see the `rbw` skill for using it without printing it; details in `/mnt/ha/AGENTS.md` § *AI Agent user*). Don't use `zhj hass::secrets-gu5a`, which is the user's personal token.

## Never print credential stores

`.storage/core.config_entries`, `.storage/auth` and `secrets.yaml` hold
passwords, OAuth and API tokens; a single `rg`/`grep -A` over them has leaked
dozens of credentials. Claude Code blocks such commands. Instead:

- Inspect config entries with `zsh -lc 'zhj hass::config-entries [--domain X]'`:
  it lists domain, title, entry id and the key names of data/options, without
  values.
- Search `/mnt/ha` with `rg -l` (file names) and `--glob '!.storage/**' --glob
  '!secrets.yaml'`; read the file you found, never the store.
- To change a value in a store, edit it in place with `jq`/`sed -i`, print
  nothing, and reload the domain.
- Validate with `zsh -lc 'zhj hass::check-config'`, not `ha core check` (which
  expands the resolved config, including `!secret` values). Read `ha core logs`
  through `grep` on a pattern, and `ha apps info` through `jq` on named fields.

## Repairs and stale warnings

For "I see a repair/warning for X", read `references/repairs.md` (how to list repairs, reload an integration, known recurring cases).

## MCP

When an MCP client is available, prefer the configured `home-assistant` MCP server for live entity state, tool-driven inspection, and control. The `zhj hass-cli` and raw API fallbacks are for local Codex/shell workflows only.
