# Passkey counters and recovery

Counter inspection and recovery use:

```bash
rbw passkey counter ENTRY --rp-id auth.example.com
rbw passkey counter ENTRY --rp-id auth.example.com --set 5
```

`--set` only advances counters. Choose a value from verified server state,
not a guessed large number. For Authelia, also inspect the matching server
credential's `sign_count` and `clone_warning`. Equal vault and server counters are normal after a successful
assertion; the next assertion must exceed the server counter. Equality alone
does not prove recovery.

Authelia persists `clone_warning`, and its go-webauthn dependency does not clear
an existing warning when a later assertion advances the counter. Once flagged,
the credential can remain rejected even with synchronized, increasing counters.
`rbw passkey counter --set` cannot clear that server flag. Diagnose from server
logs and credential state before repeating attempts; the portal's generic
"Failed to initiate security key sign in process" can mask a clone rejection.

Recovery requires re-registration or a targeted server repair after verifying
that the flagged credential is the intended vault passkey and that the warning
came from the known counter mismatch. Before a manual database repair, create a
restricted SQLite backup using the backup API, preserve `sign_count`, and clear
only that credential's warning. Sync the ordinary Bitwarden client before
retrying, then verify site acceptance and the server's counter and warning.
A completed rbw writeback proves vault synchronization, not server acceptance.

Never inject a passkey on a relying party the ordinary Bitwarden client also
signs in to (Authelia, auth.brkn.lol) unless that client's counter is known to
follow: the injector advances the server's `sign_count` past what the client
sends, and the client is then rejected as a clone (seen 2026-10-15: server and
vault at 25, client below, warning latched). The repair used there: SQLite
backup under `/mnt/data/backups/authelia/`, then `clone_warning=0` and
`sign_count=0` for that one credential, so the client's next assertion passes.

The server rejects competing updates using its revision timestamp; rbw also
locks the item against concurrent injections on the same machine. Avoid
simultaneous use of the same passkey across clients, since counters cannot
serialize assertion delivery across browsers.
