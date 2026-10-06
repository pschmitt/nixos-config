---
name: rbw
description: >-
  Unlock rbw (Bitwarden CLI) via a Home Assistant phone notification.
  Use when rbw commands fail with "not unlocked", before calling
  rbw::get/rbw::find, or whenever the vault needs to be unlocked.
---

# rbw

Use this skill when rbw needs to be unlocked before a command can run.

## This is a private fork

`rbw` here is built from `github:pschmitt/rbw` (flake input `rbw`), a
personal fork of the upstream `doy/rbw` project -- not the stock upstream
build. It carries extra features on top of upstream, notably: item
archiving (`rbw archive`/`rbw unarchive`, `--archived`/`--include-archived`
on `list`/`search`), trash restore (`rbw restore`, `--trashed`/
`--include-trashed`), a `--force` flag on `rbw remove`/`rbw delete` for an
actual permanent delete (plain `remove` is a safe soft-delete-to-trash),
`rbw collection <subcommand>` for organization collections, and a TUI
(`rbw tui`). When in doubt about a command's exact behavior, check
`rbw <command> --help` or the fork's own `README.md`/`TODO.md`
(`~/devel/private/pschmitt/rbw.git`) rather than assuming upstream
`doy/rbw` documentation applies.

## Hermes Agent

When running in Hermes, prefer the configured `bitwarden` MCP server instead
of `rbw`. Hermes already receives its Bitwarden session through its protected
service configuration, so do not invoke the HA phone-unlock webhook or ask for
the master password. Retrieve only the required vault field and never expose a
credential in a response, URL, committed file, or command output.

The remaining instructions apply to local Codex and shell workflows.

## Check unlock status

```bash
rbw unlocked
```

Returns 0 if unlocked, non-zero if locked.

## Request unlock via Home Assistant

POST to the HA webhook to send an actionable notification to the phone.
On **Accept**, HA SSHes to the target host and pipes the master password
from HA secrets to `rbw unlock --stdin`.

```bash
curl -fsS -X POST "http://10.5.1.1:8123/api/webhook/rbw_unlock_request" \
  -H "Content-Type: application/json" \
  -d "{\"host\": \"${HOST:-fnuc}\", \"agent\": \"Claude\"}"
```

The `host` field is optional and defaults to `fnuc`. Known short names that
HA maps to SSH targets (`<name>.lan`): `fnuc`, `ge2`, `x13`, `gk4`.

The `agent` field is shown in the phone notification (defaults to `Claude`
if omitted).

## Poll for unlock

After triggering the webhook, poll until unlocked (2-minute timeout):

```bash
for i in $(seq 1 24); do
  rbw unlocked 2>/dev/null && break
  sleep 5
done
rbw unlocked || { echo "rbw unlock timed out"; exit 1; }
```

## Full unlock flow (copy-paste ready)

```bash
if ! rbw unlocked 2>/dev/null; then
  echo "Requesting rbw unlock on ${HOST:-fnuc} via Home Assistant..."
  curl -fsS -X POST "http://10.5.1.1:8123/api/webhook/rbw_unlock_request" \
    -H "Content-Type: application/json" \
    -d "{\"host\": \"${HOST:-fnuc}\", \"agent\": \"Claude\"}" || {
    echo "Failed to reach HA webhook" >&2; exit 1
  }
  echo "Waiting for Accept tap on phone (up to 2 minutes)..."
  for i in $(seq 1 24); do
    rbw unlocked 2>/dev/null && { echo "rbw unlocked"; break; }
    sleep 5
  done
  rbw unlocked || { echo "rbw unlock timed out"; exit 1; }
fi
```

## Editing entries non-interactively

`rbw edit` (2.17.x) never launches `$EDITOR`/`$VISUAL` when stdin is not a
TTY; it reads the new entry from stdin instead. Errors such as
`failed to parse YAML: missing field name` or `EOF while parsing a value` mean
it got empty stdin. With a TTY, `VISUAL=nvim` just hangs an agent shell.

To update an entry (for example the notes of a secure note) from a script:

```bash
rbw get --raw "<item>" \
  | jq --rawfile n new-notes.txt '.data.type="secure_note" | .notes=$n' \
  | rbw edit --json "<item>"
rbw sync
```

- `rbw get --raw` reports the type as `SecureNote`, but `edit --json` only
  accepts `login`, `card`, `identity`, `secure_note` and `ssh_key`.
- Back up the old notes and do a no-op round trip (`cmp` afterwards) before the
  first real write.
- `rbw get` appends a trailing newline, so each round trip adds one extra
  newline to the note; harmless for YAML.
- Never `pkill -f 'rbw edit'` from an agent shell; the pattern matches the
  shell's own command line.

## Passkeys in browser automation

For using passkeys stored in `rbw` to authenticate automated browser sessions
(Playwright MCP), see the [browser-passkey skill](../browser-passkey/SKILL.md).

