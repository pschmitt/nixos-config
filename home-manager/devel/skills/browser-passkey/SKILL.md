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
  passkey is offered ("Type the text you hear or see"). Reproduced twice on
  `playwright-browserless-fnuc` (home IP): the fresh `accounts.google.com`
  page has no CAPTCHA, but it appears right after submitting the email, even
  with a valid virtual authenticator loaded, so it is not caused by repeated
  attempts. That is a bot check; do not try to solve or bypass it. Either
  hand the task to the user (a file to import, an API route), or, if they are
  willing, let them solve it in the live view (see "When a human has to step
  in"). Decide that early, before a passkey is exposed for nothing.
- **Verified end to end on Authelia** (`auth.brkn.lol`, 2026-10-08, via
  `playwright-browserless-fnuc`): inject, open the login page, click "Sign in
  with a passkey", and Authelia accepts the virtual passkey as first factor
  ("Hi <name>"). Authelia's `two_factor` policy then still asks for the
  password. Do not type it yourself from the vault into the page (it would
  appear in your tool call): let the user enter it in the live view (see
  below), or fetch it into the page with the same one-shot-server trick.

## When a human has to step in (CAPTCHA, approval, 2FA on a device)

Never solve or bypass a bot check yourself. If the user is willing to do it,
notify them with a link that opens the Browserless **live view of your own
page**, so they can click and type in the very session you are driving:

```bash
"$SKILL_DIR/scripts/ask-human.sh" --match 'accounts\.google\.com' --via both \
  "Solve the Google CAPTCHA, then tap Next"
```

- **Direct link:** `--match REGEX` picks your page by URL from the Browserless
  page list (it must match exactly one page: the browser is shared with other
  agents, e.g. an open HR WORKS tab), or pass `--page ID` with your own page id:
  `(await (await page.context().newCDPSession(page)).send('Target.getTargetInfo')).targetInfo.targetId`.
  The link is `https://browserless.<host>.ts.brkn.lol/devtools/inspector.html?wss=<same host>/devtools/page/<id>`:
  Chromium DevTools with a screencast of the page you can click and type into.
  It takes about 10 seconds to initialise. Without `--match`/`--page` the link
  goes to the general `/debugger/` page, which only lists the sessions.
- **Channels:** `--via push` (default; `notify.mobile_app_pixel_11_pro`, the
  user's main phone, `--phone` overrides), `--via signal` (`notify.signal_me`,
  with the `[BROWSER HANDOFF | CLAUDE CODE]` heading CONTEXT.md asks for) or
  `--via both`.
- **Host:** `--host fnuc` (default), `rofl-13` or `rofl-14`, matching the
  Playwright MCP server you use. Tailnet only without a login; Authelia protects
  it elsewhere.

Then wait without touching the page, and re-check it (`browser_snapshot`)
before continuing. Whatever the user types in that view (a password, a code)
never passes through you, which is the point. Keep the session open meanwhile:
Browserless ends it after an hour or when the MCP server disconnects.

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
