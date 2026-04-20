---
name: home-assistant
description: Use when working with the Home Assistant configuration for the `hv` VM, especially for YAML config changes, `config.d/` edits, hass-cli inspection, API calls, Lovelace-facing text, and validation before or after changes. Read `references/conventions.md` before editing and avoid direct `.storage/` changes unless the user explicitly approves them.
---

# Home Assistant

Use this skill for Home Assistant configuration and inspection work.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Prefer `hass-cli` for shell-driven inspection and API calls.
3. On most hosts, the Home Assistant filesystem is mounted at `/mnt/hass`.
4. If authentication is needed, prefer:

```bash
zhj hass-cli
```

5. If a Home Assistant token is needed, use:

```bash
zhj hass::secrets-gu5a
```

## Workflow

1. Identify whether the task is config editing, API inspection, Lovelace work,
   or VM or host access.
2. Read `references/conventions.md` and load only the relevant sections for the
   task.
3. Prefer focused edits in `config.d/` and avoid unrelated formatting churn in
   YAML-heavy files.
4. Validate Home Assistant changes before and after editing when practical.
5. Avoid `.storage/` changes unless the user explicitly approves them.

## Reference map

- `references/conventions.md`: Canonical Home Assistant repo conventions and
  access notes.

## Safety rules

- Do not rewrite generated or unrelated sections just to normalize formatting.
- Expect unrelated local changes in the repo and do not revert them unless the
  user explicitly asks.
- Treat `.storage/` as a last resort and require explicit user confirmation
  before touching it.
