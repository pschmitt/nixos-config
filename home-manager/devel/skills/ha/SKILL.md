---
name: ha
description: Use when working with the Home Assistant configuration for the `hv` VM, especially for YAML config changes, `config.d/` edits, MCP-backed inspection or control, hass-cli inspection, API calls, Lovelace dashboard editing (`.storage/lovelace.*`), and validation before or after changes. Read `AGENTS.md` in the repo before editing.
---

# Home Assistant

Use this skill for Home Assistant configuration and inspection work on the `hv` VM.

## Repository

The HA config repo is mounted at `/mnt/hass` (SSHFS). Read `AGENTS.md` there for all access details, working conventions, and Lovelace editing procedures.

## Lovelace / Dashboard Editing

Dashboards in storage mode live at `/mnt/hass/.storage/lovelace.<url-slug>` (underscores, e.g. `lovelace.main_dashboard`).

**Writing the file on disk does NOT update HA's in-memory cache.** After any manual `.storage/` edit you must push the new config via a `lovelace/config/save` WebSocket message — analogous to `python3 build.py --storage --push` for the mi-casa dashboard.

- **Mi-casa** (`lovelace.mi_casa`) is generated — edit `dashboards/casa/build.py` and re-run `python3 build.py --storage --push`, never edit the storage file directly.
- **Other dashboards** — parse with `json`, mutate, write back, then send the WS push. See the full script in `/mnt/hass/AGENTS.md` § *Lovelace / Dashboard Editing*.
- Get the token with `read URL TOKEN < <(zsh -lc 'zhj hass::secrets-gu5a')`.

## MCP

When an MCP client is available, prefer the configured `home-assistant` MCP server for live entity state, tool-driven inspection, and control. Fall back to `zhj hass-cli` or raw API calls otherwise.
