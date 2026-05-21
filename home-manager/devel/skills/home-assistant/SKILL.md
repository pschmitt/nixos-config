---
name: home-assistant
description: Use when working with the Home Assistant configuration for the `hv` VM, especially for YAML config changes, `config.d/` edits, MCP-backed inspection or control, hass-cli inspection, API calls, Lovelace dashboard editing (`.storage/lovelace.*`), and validation before or after changes. Read `references/conventions.md` before editing.
---

# Home Assistant

Use this skill for Home Assistant configuration and inspection work.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Prefer the configured `home-assistant` MCP server for live entity state, tool-driven inspection, and control when an MCP client is available.
3. Prefer `hass-cli` for shell-driven inspection, validation, and API calls outside MCP.
4. On most hosts, the Home Assistant filesystem is mounted at `/mnt/hass`.
5. If authentication is needed, prefer:

```bash
zhj hass-cli
```

6. If a Home Assistant token is needed, use:

```bash
zhj hass::secrets-gu5a
```

## Workflow

1. Identify whether the task is config editing, live inspection or control, API inspection, Lovelace work, or VM or host access.
2. Read `references/conventions.md` and load only the relevant sections for the task.
3. If the MCP server is available, use it first for live state lookups and safe tool-mediated actions.
4. Use `zhj hass-cli` or raw API calls when MCP is unavailable, insufficient, or when validation needs shell output.
5. Prefer focused edits in `config.d/` and avoid unrelated formatting churn in YAML-heavy files.
6. Validate Home Assistant changes before and after editing when practical.
7. For Lovelace dashboard edits, go directly to `.storage/lovelace.*` — no
   extra confirmation needed when the user asks to change a dashboard. After
   writing the file, push changes live via the `lovelace/config/save`
   WebSocket call (see `references/conventions.md` → "Lovelace / Dashboard
   Editing" for the snippet). Avoid all other `.storage/` changes unless the
   user explicitly approves them.

## Reference map

- `references/conventions.md`: Canonical Home Assistant repo conventions and
  access notes.

## Safety rules

- Do not rewrite generated or unrelated sections just to normalize formatting.
- Expect unrelated local changes in the repo and do not revert them unless the
  user explicitly asks.
- `.storage/lovelace.*` edits are fine when the user asks to change a
  dashboard. All other `.storage/` changes require explicit user confirmation.
