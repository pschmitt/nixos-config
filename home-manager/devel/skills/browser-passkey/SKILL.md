---
name: browser-passkey
description: Authenticate automated browser sessions (Playwright MCP) using WebAuthn passkeys stored in rbw / Vaultwarden. Use whenever an automated browser task encounters a passkey, WebAuthn, or FIDO2 login challenge.
---

# Browser Passkey Authentication

Use this skill when an automated browser session driven by Playwright MCP
(`playwright-browserless-fnuc`, `playwright-browserless-rofl-13`,
`playwright-browserless-rofl-14`; each attaches to that host's Browserless
Chromium over CDP) hits a WebAuthn passkey or FIDO2 login challenge.

In these containerized browsers there is no USB key, no phone proximity check
and no platform authenticator. Instead, a CDP `WebAuthn` virtual authenticator is
created in the page and seeded with the passkey private key from `rbw`. With
`automaticPresenceSimulation` and `isUserVerified`, Chromium signs the challenge
without any human interaction.

## Read this first: what does not work

Verified on `playwright-browserless-fnuc` and `-rofl-13` (2026-10):

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
  `~/.cache/playwright-mcp/<server>/` and the nixos-config checkout.
- **Never `echo`, `cat` or return the credential**, and never print
  `rbw get --raw` output for passkey entries.
- **Google sign-in shows a CAPTCHA** to these automated browsers before any
  passkey is offered ("Type the text you hear or see"). That is a bot check;
  do not try to solve or bypass it. Google accounts cannot be signed in this
  way. Hand the task to the user (or find an API/import route) instead.

## Leak-free workflow

The credential travels `rbw` -> one-shot local HTTP server -> the browser's own
`fetch` -> CDP. It never appears in a tool call or its output.

### Step 0: prerequisites

- `rbw` must be unlocked. `rbw unlocked` prints nothing and exits 0 when it is;
  if it is locked, follow the `rbw` skill (Home Assistant phone notification).
- Find the exact entry. Names can be ambiguous (several `google.com (...)`
  entries): `rbw get "https://accounts.google.com" "user@example.com" --raw`
  fails with a list of matches that includes each entry's `uid`. Prefer the uid.
- Check, without printing secrets, that the entry has a passkey:
  `rbw get UID --raw | jq '{passkeys: ((.data.fido2_credentials // [])|length)}'`

### Step 1: serve the passkey once

Run the helper in the background (it prints a one-time URL on its first line
and exits after serving a single request, or after 120 s):

```bash
SKILL_DIR=...   # the "Base directory for this skill" shown above
"$SKILL_DIR/scripts/passkey-serve.sh" UID_OR_NAME > /tmp/passkey.url &
sleep 1; cat /tmp/passkey.url
```

The URL contains a random token. It is bound to the docker0 address by default
(`172.17.0.1`), which is how `playwright-browserless-fnuc`'s browser reaches the
host. For `-rofl-13` / `-rofl-14` pass `--bind ADDR` with an address of this
machine that those hosts can reach (tailnet or LAN IP). `--rp-id` picks one
passkey when the entry has several.

### Step 2: inject it, before opening the login page

`fetch` runs inside the browser (via `page.evaluate`), so do it on `about:blank`
(an `https://` page cannot fetch an `http://` URL). Only the URL is in the code:

```javascript
async (page) => {
  await page.goto('about:blank');
  const cred = await page.evaluate((u) => fetch(u).then((r) => r.json()), 'URL_FROM_STEP_1');
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');
  const { authenticatorId } = await cdp.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2', transport: 'internal',
      hasResidentKey: true, hasUserVerification: true, isUserVerified: true,
      automaticPresenceSimulation: true,
      defaultBackupEligibility: true, defaultBackupState: true,
    },
  });
  await cdp.send('WebAuthn.addCredential', { authenticatorId, credential: cred });
  const { credentials } = await cdp.send('WebAuthn.getCredentials', { authenticatorId });
  // Return counts and ids only, never `cred`.
  return { authenticatorId, rpId: cred.rpId, stored: credentials.length };
}
```

Verified: the authenticator **survives navigation and later tool calls** (a
fresh `newCDPSession` can still `getCredentials` for the same
`authenticatorId`), so inject once, then navigate to the login page and click
"Sign in with a passkey". A Browserless session ends when the MCP server
disconnects or after one hour; inject again in each new session.

### Step 3: log in

`browser_navigate` to the site, click the passkey / "Use your passkey" button.
`navigator.credentials.get()` is then signed silently. (The credential's
`rpId` must match the site: a `google.com` passkey only works on `google.com`.)

### Step 4: clean up

When you are done, remove the credential from the browser:

```javascript
async (page) => {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('WebAuthn.enable');
  await cdp.send('WebAuthn.removeVirtualAuthenticator', { authenticatorId: 'ID' });
}
```

then `browser_close`. Do not leave a signed-in session for a high-value account
(Google, a password manager, ...) in a shared remote browser.

## Technical details

- `key_value` in rbw is a PKCS#8 DER EC (`prime256v1`) private key in
  URL-safe base64; CDP wants standard padded base64 (`-`->`+`, `_`->`/`).
- `credential_id` may be a UUID string (Bitwarden): CDP wants the base64 of its
  raw bytes. The helper converts both; do not redo it by hand.
- The helper script (`scripts/passkey-serve.sh`) is the only place the key is
  handled; it prints nothing but the one-time URL.

## Security

- Treat the passkey private key like a password: never in a tool call, a file
  under `~/.cache/playwright-mcp/`, a log, or model output.
- If a key was exposed anyway, say so and have the user delete that passkey on
  the site's security page and register a new one.
