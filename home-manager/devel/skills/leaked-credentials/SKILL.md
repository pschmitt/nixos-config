---
name: leaked-credentials
description: Handle a credential that ended up where it should not be (tool output, transcript, chat, a file, a log). Use as soon as you notice a password, token, API key, private key, passkey or session cookie exposed, or when the agent-secret-scan hook reports credentials in a tool result.
---

# Leaked credentials

The prevention rules in `CONTEXT.md` come first. This skill is what to do once a credential has leaked anyway, even briefly and even if you caused it. Act **as soon as you notice**.

## Steps

1. Tell the user plainly what was exposed and where, naming the credential (entry or key path), never its value.
2. Add a row under *Open* in the Obsidian note `homelab/🚨 Leaked credentials.md` (vault `/home/pschmitt/Documents/notes`; use the `obsidian` skill, or edit the file directly when the MCP cannot reach the vault): date, what, where it leaked, how to rotate, status. Never write the value into the note.
3. Contain what you can: revoke sessions and tokens you created, shred temporary files. Rotate the credential yourself only when that can be done without the value passing through your context (see `just sops-rotate` and the credential rotation note); otherwise leave it open for the user.
4. When something is rotated and verified, move its row to *Resolved*.

## What counts

Not a credential, so no row needed: public SSH host-key fingerprints, SSH-derived age recipients (`age1...`), GPG key IDs and fingerprints, and SOPS ciphertext. `just deploy` and `gpg::auto-unlock` already mask them; if you still see one, carry on and do not log it.

Everything else that authorizes access or identifies a person or device (tokens, passwords, seeds, signed URLs, webhook IDs, serials, MACs, IEEE addresses) still counts.

## The hooks

`agent-secret-guard` (PreToolUse) blocks risky Bash commands and `agent-secret-scan` (PostToolUse) warns about credentials in tool results; it also masks MCP results in Claude Code. If a command is blocked, use the suggested safe form; do not work around the hook.
