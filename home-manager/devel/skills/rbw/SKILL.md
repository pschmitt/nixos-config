---
name: rbw
description: >-
  Use rbw (Bitwarden CLI) safely: unlock it via a Home Assistant phone
  notification, and pass credentials to commands without printing them. Use
  when rbw commands fail with "not unlocked", when the vault needs to be
  unlocked, or whenever another skill names an rbw entry/field to use.
---

# rbw

Use this skill when the `rbw` CLI needs to be unlocked before a command can
run. For vault operations, call `rbw` directly; do not use legacy `zhj
rbw::get` or `zhj rbw::find` wrappers.

## This is a private fork

`rbw` here is built from `github:pschmitt/rbw` (flake input `rbw`), a
personal fork of the upstream `doy/rbw` project -- not the stock upstream
build. It carries extra features on top of upstream, notably: item
archiving (`rbw archive`/`rbw unarchive`, `--archived`/`--include-archived`
on `list`/`search`), trash restore (`rbw restore`, `--trashed`/
`--include-trashed`), a `--force` flag on `rbw remove`/`rbw delete` for an
actual permanent delete (plain `remove` is a safe soft-delete-to-trash),
`rbw collection <subcommand>` for organization collections, `--redact`
(hide secrets, see below), multiple accounts, and a TUI (`rbw tui`). When in doubt about a command's exact behavior, check
`rbw <command> --help` or the fork's own `README.md`/`TODO.md`
(`~/devel/private/pschmitt/rbw.git`) rather than assuming upstream
`doy/rbw` documentation applies.

## Prefer the `rbw` MCP server

When the `rbw` MCP tools are available (`mcp__rbw__*`, or `rbw_*` in other
harnesses), use them instead of shelling out: they cover the whole CRUD
surface and keep secrets masked by default.

- Find: `search` (term, or `url` for a page's logins), `list` (filters,
  `older_than`), `get` (masked JSON, or one non-secret `field`), `status`.
- Change: `create` (any type; `generate` stores a new password without
  returning it), `update` (`rbw set`: password, fields, notes, URIs, TOTP,
  `if_revision`), `edit` (JSON merge patch for card/identity/SSH fields or
  removing fields), `archive`/`unarchive`, `delete` (trash; `permanent` is
  irreversible), `restore`, `history_restore`, `move`, attachments,
  `collection_assign`.
- Use a secret: `secret_to_file` (field, or `totp_code`) writes it to a 0600
  file; use it as `"$(cat FILE)"` and delete the file. Never `cat` it bare.
- Anything else (sends, orgs, config): the `rbw` passthrough tool, redacted.
- Never pass back a masked `••••••••` value; leave unchanged fields out.
- A locked vault: unlock via Home Assistant below, then retry.

The rest of this file is for shell use when the MCP isn't loaded.

## Look without seeing secrets: `--redact`

Add the global `--redact` flag (aliases `--mask`, `--no-secrets`; or export
`RBW_REDACT=1`) whenever you only need to find, identify or inspect entries.
It masks every secret as `••••••••` -- passwords, TOTP seeds, card numbers and
codes, SSH private keys, passkey keys, hidden fields, identity numbers, old
passwords and **notes** -- in `get`, `show`, `history`, `list`, `search`
(including `--json`/`--yaml`), the `set` diff and the TUI. Commands whose job is
to output a secret (`code`, `inject`, `run`, `copy`, `export`, `edit`,
`attachment get`, `passkey assert`, `get` without `--field`, `--insecure`, ...)
refuse instead. So `rbw --redact show NAME` or `rbw --redact get --json NAME`
is safe to run in a transcript, while `rbw get --field username NAME` still
works. Drop the flag only for the call that really needs the value, and pipe
that value to its consumer instead of printing it.

`rbw search NAME --json` and `rbw get --raw` without `--redact` have printed whole
vault entries (passwords, PATs, passkey private keys, TOTP seeds) into
transcripts. Claude Code blocks them; always add `--redact` for lookups.

## Using a credential from another skill

Other skills only name the entry and field they need (for example
"entry `Netbox (AI Agent)`, field `API Token`") and point here. To use one:

1. Check the entry exists without exposing anything:
   `rbw --redact get --json "<entry>"` (lists the field names, masks values).
2. Capture the value into a shell variable in the same command that uses it.
   Never let it reach stdout, a file in the repo, a URL or a command line:

   ```bash
   token="$(rbw get --field "API Token" "Netbox (AI Agent)")"
   # header from a file descriptor, not argv
   curl -fsS -H @<(printf 'Authorization: Token %s\n' "$token") "$url"
   # or hand it to a tool through its environment
   NETBOX_TOKEN="$token" some-cli ...
   ```

   Field names: `password` and `username` are built in; anything else is a
   custom field and is case-sensitive. `rbw code "<entry>"` prints the
   current TOTP code: capture it the same way.
3. Bare `rbw get "<entry>"`, `rbw get --json` (without `--redact`) and
   `rbw get --field ...` outside `$(...)` print the secret into the
   transcript. Don't run them.
4. Browser logins never take a value from the shell: use the browser MCP's
   `browser_fill_secret entry=... field=password|username|totp` when the
   entry is allowed there, otherwise hand the login to the user (see the
   [browser-login skill](../browser-login/SKILL.md),
   [human handoff](../browser-login/references/human-handoff.md)).

## Several accounts

`get`, `show`, `search` and `list` look in every configured account; from
2.32 `edit`, `set`, `remove`, `archive`, `unarchive`, `history` and
`attachment` do too and act on the account that holds the entry. Older
builds only searched the primary account for those, failing with `no entry
found` even though `get` worked: pass `-a ACCOUNT` (for example `-a wiit`
for the work vault) there. `collection assign|unassign` and `move` still
need `-a`.

## Hermes Agent

When running in Hermes, prefer the configured `bitwarden` MCP server instead
of `rbw`. Hermes already receives its Bitwarden session through its protected
service configuration, so do not invoke the HA phone-unlock webhook or ask for
the master password. Retrieve only the required vault field and never expose a
credential in a response, URL, committed file, or command output.

The remaining instructions apply to local Codex and shell workflows.

## Unlock via Home Assistant

`rbw unlocked` returns 0 when the vault is unlocked. If it is locked, POST to
the HA webhook: it sends an actionable notification to the phone, and on
**Accept** HA SSHes to the host and pipes the master password from HA secrets
to `rbw unlock --stdin`. Then poll for up to 5 minutes. Give the tool call a
longer timeout than that (e.g. 330000 ms); agent shells often default to 2
minutes and would cut the wait short.

```bash
if ! rbw unlocked 2>/dev/null; then
  echo "Requesting rbw unlock on ${HOST:-fnuc} via Home Assistant..."
  curl -fsS -X POST "http://10.5.1.1:8123/api/webhook/rbw_unlock_request" \
    -H "Content-Type: application/json" \
    -d "{\"host\": \"${HOST:-fnuc}\", \"agent\": \"Claude\"}" || {
    echo "Failed to reach HA webhook" >&2; exit 1
  }
  echo "Waiting for Accept tap on phone (up to 5 minutes)..."
  for i in $(seq 1 60); do
    rbw unlocked 2>/dev/null && { echo "rbw unlocked"; break; }
    sleep 5
  done
  rbw unlocked || { echo "rbw unlock timed out"; exit 1; }
fi
```

- `host` is optional and defaults to `fnuc`. Known short names that HA maps
  to SSH targets (`<name>.lan`): `fnuc`, `ge2`, `x13`, `gk4`.
- `agent` is shown in the phone notification (default `Claude`).

## Writing to the vault

To edit an entry or set a password or custom field, read
[references/writing-entries.md](references/writing-entries.md) first. Never
put a secret on the `rbw` command line, and never let `rbw edit` open an
editor in an agent shell.

## Passkeys in browser automation

For using passkeys stored in `rbw` to authenticate automated browser sessions
(Playwright MCP), see the [browser-login skill](../browser-login/SKILL.md).

