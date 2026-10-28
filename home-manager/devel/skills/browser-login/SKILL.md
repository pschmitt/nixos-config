---
name: browser-passkey
description: Authenticate automated browser sessions (Playwright MCP) using WebAuthn passkeys stored in rbw / Vaultwarden. Use whenever an automated browser task encounters a passkey, WebAuthn, or FIDO2 login challenge.
---

# Browser Passkey Authentication

Use this skill when an automated browser session driven by Playwright MCP
(the `browser-daemon` MCP; it attaches to a browser-daemon node's Chromium over CDP,
`browser_use node=...` picks the node) hits a WebAuthn passkey or FIDO2 login challenge.

In these remote browsers there is no USB key, no phone proximity check
and no platform authenticator. Instead, `rbw passkey inject` creates a CDP `WebAuthn` virtual authenticator
in the page and seeds it directly from the vault. With
`automaticPresenceSimulation` and `isUserVerified`, Chromium signs the challenge
without any human interaction.

`$SKILL_DIR` below is this skill's directory; set it before running a script,
e.g. `SKILL_DIR=~/.config/claude/skills/browser-passkey` (Claude Code),
`~/.config/claude-work/skills/browser-passkey` (Claude Work) or
`~/.config/codex/skills/browser-passkey` (Codex).

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
  willing, let them solve it in the live view (see "When a human has to step
  in"). Decide that early, before a passkey is exposed for nothing.
- **Verified end to end on Authelia** (`auth.brkn.lol`, 2026-10-08, via
  the fnuc node): inject, open the login page, click "Sign in
  with a passkey", and Authelia accepts the virtual passkey as first factor
  ("Hi <name>"). Authelia's `two_factor` policy then still asks for the
  password. Never type it yourself through a browser tool (it would appear
  in your tool call): use `browser_fill_secret` when the entry is allowed
  for agents (its tool description lists them), otherwise let the user
  enter it in the live view (see below).

## When a human has to step in (CAPTCHA, approval, 2FA on a device)

Never solve or bypass a bot check yourself. If the user is willing to do it,
notify them with a link that opens the browser-daemon **live view of your own
page**, so they can click and type in the very session you are driving:

```bash
"$SKILL_DIR/scripts/ask-human.sh" --match 'accounts\.google\.com' --via both \
  "Solve the Google CAPTCHA, then tap Next"
```

- **Direct link:** `--match REGEX` picks your page by URL from the browser-daemon
  page list (it must match exactly one page: the browser is shared with other
  agents, e.g. an open HR WORKS tab), or pass `--page ID` with your own page id:
  `(await (await page.context().newCDPSession(page)).send('Target.getTargetInfo')).targetInfo.targetId`.
  There are two links to the same view, chosen with `--url auto|mesh|public`
  (`auto`, the default, asks Home Assistant where the user is):
  `mesh` = `https://browser.<host>.nb.brkn.lol/handoff/?page=<id>` (mesh
  only, no login, used when the user is home) and `public` =
  `https://browser.<host>.brkn.lol/handoff/?page=<id>` (reachable from anywhere,
  Authelia two-factor, owner only; used when away, since the user is then not on
  the mesh). The public vhost lives on rofl-10
  (`hosts/rofl-10/browserless-public.nix`) and proxies only `/handoff/`,
  `/json/list` and the websocket of one page, never browser-daemon's own API.
  The view is a small phone-friendly page served by browser-daemon (source:
  `handoff.html` in the browser-daemon repository): tap = click, drag
  = scroll, back/forward/reload, and tapping a text field raises the phone's
  native keyboard (type and key hint mirror the field: email, password, ...;
  the remote page is resized to the phone like a real mobile browser, toggle
  in the top bar). Without `--match`/`--page` it shows a list of pages to pick.
  Use the page-specific `/handoff/` link for mobile interaction.
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
browser-daemon owns session lifetime; keep the CDP connection open while
waiting for the user.

## Passkey injection and counter synchronization

Use `rbw passkey inject` for automated passkey logins. It fetches the current
vault counter, reserves the next value on the server before enabling the
virtual authenticator, sends the private key directly to Chromium via CDP,
and writes back the browser assertion counter. The reservation survives a
browser disconnect or timeout. The virtual authenticator is removed after
one assertion; inject again for another assertion.

Do not seed a credential with `signCount: 0` or copy its private key into
Playwright code. Browser counters must be synchronized with the vault: a
fresh virtual authenticator otherwise repeats a counter and Authelia flags
the credential as cloned. Bitwarden increments and saves nonzero counters
and syncs before using them. After enabling counters on a previously zero
credential, refresh/sync the ordinary Bitwarden client before using it.

1. Ensure rbw is unlocked (`rbw unlocked`; use the `rbw` skill if needed).
2. Identify your exact browser page ID using Playwright:

   ```javascript
   async (page) => {
     const cdp = await page.context().newCDPSession(page);
     const result = await cdp.send('Target.getTargetInfo');
     await cdp.detach();
     return { pageId: result.targetInfo.targetId };
   }
   ```

3. Start the command while keeping Playwright's page open:

   ```bash
   rbw passkey inject ENTRY --rp-id auth.example.com \
     --cdp-url https://browser.fnuc.nb.brkn.lol --page-id PAGE_ID
   ```

   Use the trusted mesh endpoint for the same host as your Playwright server
   (`fnuc`, `rofl-13`, or `rofl-14`). Do not target another agent's page.
   The command prints `Passkey ready` once the reservation is saved and the
   authenticator is enabled. Keep the process running while driving the login.
   It waits 120 seconds by default (`--timeout` accepts up to 3600).

4. Click the passkey sign-in button. Wait for the rbw process to report
   `vault synchronized` and exit successfully. An assertion being generated
   does not itself prove the site accepted the login; check the page too.
   A writeback error requires attention before further logins. If cleanup
   fails, close your browser page. Never leave a privileged authenticated
   session open after finishing work.

Counter inspection, recovery, and the Authelia clone-warning trap (never
inject a passkey on a relying party your ordinary Bitwarden client also uses)
are in [`references/counters.md`](references/counters.md). Read it before
any `--set` or server-side repair, and before injecting on `auth.brkn.lol`.

## Signing in without a person: agent-passkey

`rbw passkey inject` arms one page, so it fails where a sign-in hops across
origins or asks for the assertion the moment a page loads. Microsoft is the
case: `login.microsoft.com/common/bridge/fido` calls `navigator.credentials.get()`
on load, answers a reload with AADSTS10040141, and a virtual authenticator armed
earlier does not follow the hop. Use `scripts/agent-passkey.mjs` instead; it
answers every passkey request of the whole browser, signed by `rbw passkey
assert` outside the browser (verified: Outlook signed in unattended):

1. Start the session (`browser_use profile=...`, navigate once) and find its
   debugging port: `browser-daemon session list --json` (`port`). For a session
   on another node, forward it first (`ssh -L PORT:127.0.0.1:PORT NODE`).
2. Start the helper in the background, before the sign-in:
   `node "$SKILL_DIR/scripts/agent-passkey.mjs" http://127.0.0.1:PORT --timeout 300 &`
   (waits for `agent-passkey: ready` on stderr).
3. Sign in as usual: type the username (secrets with `browser_fill_secret`,
   never in tool arguments), click Next. The passkey step completes by itself.
4. Stop the helper (`kill` its job) when done; it also exits after `--timeout`.

The origin passed to rbw comes from the browser's target list, never from page
script, and rbw refuses an origin outside the passkey's relying party. Run one
helper per browser: two make parallel assertions and rbw's item lock rejects one
("another passkey injection is active"). Autofill (conditional) requests are left
to the browser. Chromium only. The Authelia clone warning (`references/counters.md`) applies here too: do
not use this for a relying party your ordinary Bitwarden client also uses.

## Passkeys in the live view (a human signing in)

When a person uses a site through the browser-daemon live view (handoff), a
passkey sign-in they start there gets a prompt in the view instead of the
browser's own dialog (which the view cannot reach). It shows whether rbw is
locked, which vault entry would be used (`rbw passkey find --rp-id SITE`:
names and users, no secrets) and a picker when several entries match.
Approving sends the request to `browser-daemon passkey-helper`, a user
service on fnuc (`hosts/fnuc/browser-daemon.nix`) that serves all nodes and
asks the phone to unlock rbw first if needed:

- Chromium sessions: it runs `rbw passkey inject` for the page, as above.
- Firefox sessions: it runs `rbw passkey assert --origin ORIGIN --challenge
  CHALLENGE`, which signs outside the browser; the page answers the site's
  `navigator.credentials.get()` with the result. The node takes the origin
  from the browser's page list, never from page script, and rbw refuses an
  origin outside the passkey's relying party.

What this means for agents:

- Without a view attached, or when the request did not follow input in the
  view within 15 s, the page's request goes to the browser unchanged, so the
  inject flow above keeps working. A human typing in the view right before
  the agent clicks the passkey button gets the prompt instead; either answer
  works ("Use passkey" also signs in).
- Google refuses sign-ins in Firefox sessions ("Couldn't sign you in")
  before any passkey is asked for; use a Chromium session for Google.
- Autofill (conditional) passkey requests are never intercepted.

## Security

- Treat the passkey private key like a password: never in a tool call, a file
  under `~/.cache/playwright-mcp/`, a log, or model output.
- If a key was exposed anyway, say so and have the user delete that passkey on
  the site's security page and register a new one.
