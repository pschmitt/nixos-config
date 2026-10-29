---
name: browser-login
description: >-
  Sign in to sites in automated browser sessions (the browser-daemon MCP)
  without exposing credentials: fill passwords, usernames and TOTP codes with
  browser_fill_secret, sign passkeys from the vault with browser_passkey, and
  hand a CAPTCHA, device approval or login to the user with browser_ask_human.
  Use whenever an automated browser task hits a login form, a
  passkey/WebAuthn/FIDO2 challenge, a CAPTCHA or a 2FA prompt.
---

# Browser login

Use this skill when an automated browser session driven by the
`browser-daemon` MCP has to sign in. The MCP does the sensitive parts itself;
nothing secret ever goes through your tool calls.

## Choose the way in

- **Username, password or TOTP code:** `browser_fill_secret entry="<rbw
  entry>" field=username|password|totp target=<ref>` (`submit=true` presses
  Enter). It reads the value from rbw, only types it on a site the entry is
  saved for, and masks it in later results. Its tool description lists the
  entries allowed for agents.
- **Passkey (WebAuthn, FIDO2, "security key", "sign in with a passkey"):**
  call `browser_passkey` (optionally `site=`), then click the site's passkey
  sign-in as usual and take a snapshot. See
  [references/passkeys.md](references/passkeys.md).
- **Anything a person must do** (a CAPTCHA or other bot check, approving on
  another device, an entry not allowed for agents): `browser_ask_human
  message="<what to do>"` sends the user a link to the live view of your page.
  Then leave the page alone, wait (`browser_wait_for`) and take a snapshot.
  See [references/human-handoff.md](references/human-handoff.md).

If the vault is locked, the MCP or the node's secret agent asks the user to
unlock it on their phone; for shell work see the `rbw` skill.

## Rules

- Never type a secret with `browser_type`, `browser_fill_form` or
  `browser_run_code_unsafe`: every call is echoed into the transcript and
  logs. Never run `rbw get` just to type a value.
- Never solve or bypass a bot check yourself. **Google sign-in** shows a
  CAPTCHA to these browsers right after the email, before any passkey is
  offered. Decide early: hand the task to the user (a file to import, an API
  route) or ask them to solve it with `browser_ask_human`.
- A password field that shows its value, a "your password is ..." line, or a
  page that copies a secret elsewhere puts it into snapshots: stop and say so.
- If a secret or a passkey key ever ends up in a tool call, a log or your
  output, say so at once and follow the leaked-credentials rules (the passkey
  must be deleted on the site and registered again).
