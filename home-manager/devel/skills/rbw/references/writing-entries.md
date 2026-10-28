# Write to the vault

How to change entries from an agent shell without an editor and without
putting a secret on a command line.

## Edit entries non-interactively

`rbw edit` never launches `$EDITOR`/`$VISUAL` when stdin is not a
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

## Set secrets without exposing them (2.18+)

Never put a real secret on the `rbw` command line (`--password VALUE` lands
in `ps`, shell history and the agent transcript). Use one of these instead;
`rbw set` syncs afterwards, so consecutive calls are safe:

```bash
rbw set -y --password-file new-pw "$item"     # or --password-env VAR,
                                               # or --password-stdin (needs -y)
rbw set -y -g -l 32 --output-file new-pw "$item"  # generate+store,
                                               # old pw -> history, nothing printed
rbw set -y --field-file api-token=token.txt "$item"  # custom field
                                               # (--field-env NAME=VAR too)
```

- `--output-file` is written (0600) only after the vault update succeeded.
- `rbw set --if-revision "$(rbw get --raw "$item" | jq -r .revision_date)"`
  refuses the update if the entry changed in the meantime.
- Roll back a rotation: `rbw history -y "$item" --restore` (or
  `--restore=N`).
- Find rotation candidates: `rbw list --older-than 1year --fields
  name,modified`, and `rbw audit [--hibp] [--json]` (weak/reused/breached;
  never prints passwords).
