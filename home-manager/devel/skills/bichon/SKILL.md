---
name: bichon
description: Use for read-only lookup of invoices, order confirmations, and related email records in the Bichon mail archive. Often used in conjunction with the NetBox skill for verifying purchase details.
---

# Bichon

Search and read archived email through the `bichon` MCP server (tools:
`list_accounts`, `list_mailboxes`, `get_mailbox_stats`, `search_emails`,
`get_email`, `list_threads`, `get_sender_summary`). The server is wired in
`home-manager/devel/ai.nix`; its token is a sops secret, so there are no
credentials to handle. If the tools are missing, fall back to
`references/conventions.md` (raw REST API with the rbw token).

## Workflow

1. Identify the need for purchase evidence (invoices, receipts, order dates).
2. Search for order numbers, product names or vendors with `search_emails`.
3. Read the relevant mails with `get_email` and extract store, order number,
   date, price and currency.
4. Hand the details to the calling task (for example NetBox).

## Safety rules

- Treat all email content as confidential.
- Read-only: the MCP server offers no write tools; never delete, move or
  modify mail through the REST API either.
