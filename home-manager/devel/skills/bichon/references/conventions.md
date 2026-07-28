# Bichon Conventions

## Access

Bichon is available at:
- `https://bichon.brkn.lol`

Retrieve credentials with the runtime-appropriate method:

- **Hermes Agent:** use the configured `bitwarden` MCP server to retrieve the
  `bichon.brkn.lol` API token. Prefer this over `rbw`.
- **Local Codex/shell:** use:

```bash
zhj rbw::get --field "API Token" bichon.brkn.lol
```

If using local rbw and it is locked, invoke the `rbw` skill first.

Notes:
- Handle retrieved credentials as secrets and do not commit them to the
  repository.
- The service configuration lives in
  [`services/bichon.nix`](/etc/nixos/services/bichon.nix).

## API

- API specification:
  `https://bichon.brkn.lol/api-docs/spec.yaml`

## Workflow

When searching for purchase information:
- Search for order confirmations, invoices, and related purchase emails.
- Extract relevant metadata (store name, order number, date, price, currency).
- Use this information to populate inventory systems like NetBox.

## Safety Rules

- Under no circumstances perform destructive actions in `bichon.brkn.lol`.
- Use it for read-only lookup of information and documents.
