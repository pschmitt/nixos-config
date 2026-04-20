---
name: netbox
description: Use when working with the NetBox inventory at netbox.brkn.lol, especially for device metadata, purchase data, product/support URLs, asset tags, device type synchronization, and radio or MAC-address modeling. Read `references/conventions.md` before making NetBox changes and treat mailbox lookups on bichon.brkn.lol as read-only.
---

# NetBox

Use this skill for NetBox inventory and metadata work.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Retrieve NetBox credentials with:

```bash
zhj rbw::get --json "Netbox (AI Agent)"
```

3. Treat retrieved credentials as secrets and never commit them.

## Workflow

1. Identify whether the task is about inventory modeling, metadata cleanup,
   purchase information, or product links.
2. Read `references/conventions.md` and load only the relevant sections for the
   task.
3. When purchase details are missing, use `bichon.brkn.lol` only for read-only
   lookup of invoices, order confirmations, and related email records.
4. Normalize the NetBox data to the conventions in the reference file before
   writing changes.
5. When changing physical connectivity on a device, update the corresponding
   device type templates as well.

## Reference map

- `references/conventions.md`: Canonical NetBox conventions for this inventory.

## Safety rules

- Never commit credentials, tokens, or exported secrets.
- Do not perform destructive actions in `bichon.brkn.lol`.
- Prefer normalized custom fields over hiding important data in comments.
