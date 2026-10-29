---
name: browser-login
description: >-
  Sign in to sites in automated browser sessions (the browser-daemon MCP)
  without exposing credentials: fill passwords, usernames and TOTP codes with
  browser_fill_secret, sign passkeys from the vault with browser_passkey, and
  hand a CAPTCHA, device approval or login to the user with browser_ask_human,
  and use a signed-in session's cookies or tokens elsewhere with browser_fetch
  and browser_export_auth. Use whenever an automated browser task hits a login
  form, a passkey/WebAuthn/FIDO2 challenge, a CAPTCHA or a 2FA prompt, or a
  task needs a browser session's login for an API, curl or a CLI.
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

## Use a browser login elsewhere

When a page is signed in and you need that login outside the browser (a
site's API, `curl`, a CLI), never read cookies or tokens with Playwright's
tools or `browser_shared_command`: their answers are logged. Instead:

- `browser_fetch url=... [method= headers= body=]` makes one request with the
  page's cookies for that address (and `bearer_storage_key=` for a token from
  its storage) and returns the answer with the values masked. Prefer this.
- `browser_export_auth [format=header|cookies|json]` writes the login to a
  private file in `$XDG_RUNTIME_DIR` that is deleted after `minutes` (default
  15). The default `header` file goes to `curl -H @FILE ...`; curl 8.22
  ignores the cookies of a jar file (`cookies`) it reads. Never `cat`, print
  or copy the file. The answer lists cookie names and the page's storage keys, so you
  can pick `storage_keys` (json) or `bearer_storage_key`.

Both work on your own page or on a shared browser's tab (`browser`, `tab`,
`daemon` from `browser_shared_nodes`, shared with control), on the sites their
tool description lists. An exported session cookie is the account: if one
ever shows up in output, it is a leaked credential.

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
