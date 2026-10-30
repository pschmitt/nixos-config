---
name: gpg-signing
description: Create GPG-signed git commits and tags without a pinentry prompt. Use before any signed commit or tag, including amend, cherry-pick and rebase, or when signing fails because the key is not unlocked.
---

# GPG signing

- Before creating any GPG-signed commit or tag (including amend, cherry-pick, and rebase), run `zsh -lc 'zhj gpg::auto-unlock'`. By default the helper unlocks every signing key referenced by `user.signingkey` in the git configs (global, `includeIf`'d such as the work key, and the current repo), skips keys already cached in gpg-agent and returns immediately when all are cached. Pass a key ID or fingerprint (`zsh -lc 'zhj gpg::auto-unlock KEY_ID'`) to unlock only that key. Each key's passphrase comes from the rbw entry whose `Key ID` field matches; if none is found it fails with an error naming the key. Do this before invoking Git; a curses pinentry prompt can corrupt the agent's terminal UI.
- If unlocking requires rbw and the vault is locked, use the `rbw` skill to unlock it first. Never enter or capture a passphrase in an agent terminal, command argument, transcript, or chat.
- After auto-unlock, check the repository's actual signing key with a prompt-free signing probe: `gpg --batch --no-tty --pinentry-mode error --local-user "$(git config user.signingkey)" --detach-sign --output /dev/null </dev/null`. Require a configured `user.signingkey` and a successful probe before invoking Git. Keys that are not referenced by a git config `user.signingkey` can be unlocked by passing them to the helper explicitly. If the probe fails, resolve the unlock problem before proceeding; never retry with interactive pinentry or disable signing.
- Keep normal interactive GPG configuration intact. Any GPG wrapper used for agent Git signing must pass `--batch --no-tty --pinentry-mode error` so an expired cache fails without opening pinentry, and must be scoped to the agent command rather than installed as a global Git/GPG setting.
