---
name: gpg-signing
description: Create GPG-signed git commits and tags without a pinentry prompt. Use before any signed commit or tag, including amend, cherry-pick and rebase, or when signing fails because the key is not unlocked.
---

# GPG signing

- Before creating any GPG-signed commit or tag (including amend, cherry-pick, and rebase), run `zsh -lc 'zhj gpg::auto-unlock'`. By default the helper unlocks every signing key referenced by `user.signingkey` in the git configs (global, `includeIf`'d such as the work key, and the current repo), skips keys already cached in gpg-agent and returns immediately when all are cached. Pass a key ID or fingerprint (`zsh -lc 'zhj gpg::auto-unlock KEY_ID'`) to unlock only that key. Each key's passphrase comes from the rbw entry whose `Key ID` field matches; if none is found it fails with an error naming the key. Do this before invoking Git; a curses pinentry prompt can corrupt the agent's terminal UI.
- If unlocking requires rbw and the vault is locked, use the `rbw` skill to unlock it first. Never enter or capture a passphrase in an agent terminal, command argument, transcript, or chat.
- After auto-unlock, check the repository's actual signing key with a prompt-free signing probe: `gpg --batch --no-tty --pinentry-mode error --local-user "$(git config user.signingkey)" --detach-sign --output /dev/null </dev/null`. Require a configured `user.signingkey` and a successful probe before invoking Git. Keys that are not referenced by a git config `user.signingkey` can be unlocked by passing them to the helper explicitly. If the probe fails, resolve the unlock problem before proceeding; never retry with interactive pinentry or disable signing.
- If the default helper reports the keys cached but the repository's signing probe fails, run `zsh -lc 'zhj gpg::auto-unlock "$(git config user.signingkey)"'` from that repository and repeat the probe. This has recovered a stale cached-key result without exposing a passphrase.
- Keep normal interactive GPG configuration intact. Any GPG wrapper used for agent Git signing must pass `--batch --no-tty --pinentry-mode error` so an expired cache fails without opening pinentry, and must be scoped to the agent command rather than installed as a global Git/GPG setting.

## Decryption keys

`gpg::auto-unlock` probes signing, so its success does not prove that an
encryption subkey is cached. If SOPS decryption still fails with no pinentry,
identify the matching secret key from the SOPS recipient metadata and the
matching rbw entry by its `Key ID` or `Key fingerprint` field. Use the `rbw`
skill to unlock the vault and inspect entry metadata without exposing values.

For an authorized decryption, a temporary SOPS GPG wrapper can supply that
entry's passphrase through a file descriptor. This also caches the decryption
subkey in gpg-agent when the agent permits caching. Export `GPG_RBW_ENTRY` as
the matched entry ID, and set `encrypted_file` to the SOPS file; select the input and
output formats to match that file. For YAML:

```bash
: "${GPG_RBW_ENTRY:?Export GPG_RBW_ENTRY}"
: "${encrypted_file:?Set encrypted_file}"
umask 077
wrapper_dir=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/gpg-sops.XXXXXXXX")
trap 'rm -r -- "$wrapper_dir"' EXIT
cat > "$wrapper_dir/gpg" <<'EOF'
#!/usr/bin/env bash
exec gpg --batch --no-tty --pinentry-mode loopback --passphrase-fd 3 "$@" \
  3< <(rbw get --raw "$GPG_RBW_ENTRY" | jq -r \
    '(.fields[]? | select(.name == "passphrase") | .value) // .data.password // empty')
EOF
chmod 700 "$wrapper_dir/gpg"
SOPS_GPG_EXEC="$wrapper_dir/gpg" sops --decrypt --input-type yaml \
  --output-type yaml "$encrypted_file" > /dev/null
```

Keep tracing off; never print the rbw response, passphrase, or decrypted
content. The wrapper contains no passphrase, is scoped to this command and is
removed afterwards. Check the SOPS exit status; if the key is hardware-backed
or the passphrase is unavailable, do not bypass its access controls.
