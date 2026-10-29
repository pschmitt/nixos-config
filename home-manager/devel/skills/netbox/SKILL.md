---
name: netbox
description: Use when working with the NetBox inventory at netbox.brkn.lol, especially for device metadata, purchase data, product/support URLs, asset tags, device type synchronization, and radio or MAC-address modeling. Read `references/conventions.md` before making NetBox changes.
---

# NetBox

Use this skill for NetBox inventory and metadata work.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Credentials: rbw entry `Netbox (AI Agent)`; fields `API Token` (REST
   API), `username` and `password` (web UI login). Use them as described in
   the `rbw` skill ("Using a credential from another skill"), never print
   them. Hermes uses its `bitwarden` MCP server for the same entry.

## Workflow

1. Identify whether the task is about inventory modeling, metadata cleanup,
   purchase information, or product links.
2. Read `references/conventions.md` and load only the relevant sections for the
   task.
3. When purchase details are missing, use the `bichon` skill for read-only
   lookup of invoices, order confirmations, and related email records.
4. Normalize the NetBox data to the conventions in the reference file before
   writing changes.
5. When changing physical connectivity on a device, update the corresponding
   device type templates as well.

## Reference map

- `references/conventions.md`: Canonical NetBox conventions for this inventory.

## Safety rules

- Never commit credentials, tokens, or exported secrets.
- Prefer normalized custom fields over hiding important data in comments.
