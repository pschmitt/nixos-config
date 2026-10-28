---
name: browser-login
description: >-
  Sign in to sites in automated browser sessions (the browser-daemon
  Playwright MCP) without exposing credentials: fill passwords, usernames and
  TOTP codes from rbw with browser_fill_secret, sign WebAuthn passkeys from
  the vault, and hand a CAPTCHA, device approval or login to the user through
  the live view. Use whenever an automated browser task hits a login form, a
  passkey/WebAuthn/FIDO2 challenge, a CAPTCHA or a 2FA prompt.
---

# Browser login

Use this skill when an automated browser session driven by the
`browser-daemon` MCP (Playwright; it attaches to a browser-daemon node's
Chromium over CDP, `browser_use node=...` picks the node) has to sign in.

`$SKILL_DIR` below is this skill's directory; set it before running a script,
e.g. `SKILL_DIR=~/.config/claude/skills/browser-login` (Claude Code),
`~/.config/claude-work/skills/browser-login` (Claude Work) or
`~/.config/codex/skills/browser-login` (Codex).

## Choose the way in

- **Username, password or TOTP code:** `browser_fill_secret entry="<rbw
  entry>" field=username|password|totp target=<ref>` (`submit=true` presses
  Enter). It reads the value from rbw itself, only types it on a site the
  entry is saved for, and masks it in later results. Its tool description
  lists the entries allowed for agents. Never type a secret with
  `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`: every call
  is echoed into the transcript and logs. Never run `rbw get` just to type a
  value.
- **Passkey (WebAuthn/FIDO2):** sign it from the vault with `rbw passkey
  inject` or `scripts/agent-passkey.mjs`; read
  [references/passkeys.md](references/passkeys.md) first.
- **Anything a person must do** (a CAPTCHA or other bot check, approving on
  another device, an entry not allowed for agents): hand it to the user in
  the live view with `scripts/ask-human.sh`; see
  [references/human-handoff.md](references/human-handoff.md).

## Read this first: what does not work

Verified on the Chromium Playwright MCPs (2026-10):

- **The code sandbox of `browser_run_code_unsafe` has no Node.** `require`,
  `process`, `Buffer`, `URL`, `atob` and global `fetch` are all undefined, and
  `await import('node:...')` fails (`ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING`).
  So the old recipe (`require('child_process')` + `rbw get` inside the snippet)
  fails with `ReferenceError: require is not defined`. Only `page` and
  `page.context()` / `newCDPSession` are available.
- **Every code the tool runs is echoed back in its output** ("Ran Playwright
  code"), including code loaded with the `filename` parameter. Embedding the
  private key in the code, or in a file loaded via `filename`, **leaks it into
  the transcript and logs**. This happened once; that passkey had to be
  rotated. `filename` is also limited to
  `~/.cache/playwright-mcp/browser/<node>-<profile or throwaway>/` and the nixos-config checkout.
- **Never `echo`, `cat` or return the credential**, and never print
  `rbw get --raw` output for passkey entries.
- **Google sign-in shows a CAPTCHA** to these automated browsers before any
  passkey is offered ("Type the text you hear or see"). Reproduced twice on
  the fnuc node (home IP; `browser_use node=fnuc`): the fresh `accounts.google.com`
  page has no CAPTCHA, but it appears right after submitting the email, even
  with a valid virtual authenticator loaded, so it is not caused by repeated
  attempts. That is a bot check; do not try to solve or bypass it. Either
  hand the task to the user (a file to import, an API route), or, if they are
  willing, let them solve it in the live view (see
  [references/human-handoff.md](references/human-handoff.md)). Decide that
  early, before a passkey is exposed for nothing.

## Security

- Treat the passkey private key like a password: never in a tool call, a file
  under `~/.cache/playwright-mcp/`, a log, or model output.
- If a key was exposed anyway, say so and have the user delete that passkey on
  the site's security page and register a new one.
