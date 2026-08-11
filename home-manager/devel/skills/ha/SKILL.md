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

**Writing the file on disk does NOT update HA's in-memory cache.** After any manual `.storage/` edit you must push the new config via a `lovelace/config/save` WebSocket message — analogous to `python3 build.py --storage --push` for the mi-casa dashboard.

- **Mi-casa** (`lovelace.mi_casa`) is generated — edit `dashboards/casa/build.py` and re-run `python3 build.py --storage --push`, never edit the storage file directly.
- **Other dashboards** — parse with `json`, mutate, write back, then send the WS push. See the full script in `/mnt/ha/AGENTS.md` § *Lovelace / Dashboard Editing*.
- Get the token with `read URL TOKEN < <(zsh -lc 'zhj hass::secrets-gu5a')`.

## MCP

When an MCP client is available, prefer the configured `home-assistant` MCP server for live entity state, tool-driven inspection, and control. The `zhj hass-cli` and raw API fallbacks are for local Codex/shell workflows only.
