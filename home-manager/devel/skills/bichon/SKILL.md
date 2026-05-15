---
name: bichon
description: Use for read-only lookup of invoices, order confirmations, and related email records on bichon.brkn.lol. Often used in conjunction with the NetBox skill for verifying purchase details.
---

# Bichon

Use this skill for searching and reading email records on `bichon.brkn.lol`.

## Workflow

1. Identify the need for purchase evidence (invoices, receipts, order dates).
2. Read `references/conventions.md` for API access and usage patterns.
3. Search for specific keywords (order numbers, product names, vendors) in the mailbox.
4. Read relevant email content to extract dates, prices, and vendor details.
5. Provide these details to other tasks (e.g., updating NetBox).

## Reference map

- `references/conventions.md`: API access and usage conventions for Bichon.

## Safety rules

- Treat all email content as confidential.
- **Read-only access only**: Do not delete, move, or modify any emails.
- Do not perform destructive actions in `bichon.brkn.lol`.
