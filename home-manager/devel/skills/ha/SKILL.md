---
name: ha
description: Use when working with the Home Assistant configuration for the `hv` VM, especially for YAML config changes, `config.d/` edits, MCP-backed inspection or control, hass-cli inspection, API calls, Lovelace dashboard editing (`.storage/lovelace.*`), and validation before or after changes. Read `AGENTS.md` in the repo before editing.
---

# Home Assistant

Use this skill for Home Assistant configuration and inspection work on the `hv` VM.

## Repository

The HA config repo is mounted at `/mnt/hass` (SSHFS). Read `AGENTS.md` there for all access details, working conventions, and Lovelace editing procedures.

## MCP

When an MCP client is available, prefer the configured `home-assistant` MCP server for live entity state, tool-driven inspection, and control. Fall back to `zhj hass-cli` or raw API calls otherwise.
