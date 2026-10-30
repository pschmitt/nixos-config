# Bichon Conventions

## Access

Bichon is available at:
- `https://bichon.brkn.lol`

Credentials: rbw entry `bichon.brkn.lol`, field `API Token`. Use it as the
`rbw` skill describes ("Using a credential from another skill"): capture it
into a variable and pass it to curl through a header file descriptor, never
print it.

```bash
token="$(rbw get --field "API Token" bichon.brkn.lol)"
curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$token") \
  "https://bichon.brkn.lol/api/..."
```

Check the auth scheme in the API specification below if `Bearer` is
rejected.

Notes:
- Handle retrieved credentials as secrets and do not commit them to the
  repository.
- The service configuration lives in `services/bichon.nix` in `nixos-config`.

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
