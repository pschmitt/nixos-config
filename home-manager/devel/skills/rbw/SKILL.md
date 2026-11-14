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

## Configuration changes stop the agent

`rbw config set` and `rbw config unset` stop the running agent so it reloads
configuration. An unlocked vault therefore becomes locked again. Finish any
configuration changes before unlocking. If a provisioning flow temporarily
changes pinentry, remove its secret input files immediately after use, but
restore the setting only after the commands needing the unlocked agent finish.

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

## Unlock via Home Assistant

Configured systems provide `rbw-request-unlock`. It reads the endpoint from a
protected runtime file provisioned by the private configuration, so it works
while the vault itself is locked. Never put that endpoint in instructions,
command arguments or tool output, and never print the runtime file.

```bash
rbw-request-unlock --agent Codex --timeout 300
```

The helper first checks `rbw unlocked`. If necessary it sends the existing
Home Assistant phone-approval request, then waits for the vault to unlock.
Phone approval remains required; it never handles or displays the master
password. Its network and polling waits are bounded. Run it in a background
execution cell and yield within 60 seconds while waiting for approval.

If the helper or its runtime file is missing, repair the private configuration
and refresh the system profile. Do not reuse a cached webhook URL or fall back
to interactive pinentry in an agent terminal. The private infrastructure skill
records the supported request hosts.

## Writing to the vault

To edit an entry or set a password or custom field, read
[references/writing-entries.md](references/writing-entries.md) first. Never
put a secret on the `rbw` command line, and never let `rbw edit` open an
editor in an agent shell.

## Passkeys in browser automation

For using passkeys stored in `rbw` to authenticate automated browser sessions
(Playwright MCP), see the [browser-login skill](../browser-login/SKILL.md).

