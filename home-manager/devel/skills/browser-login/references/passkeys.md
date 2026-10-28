# Passkeys in automated browsers

In these remote browsers there is no USB key, no phone proximity check and
no platform authenticator. Instead, `rbw passkey inject` creates a CDP
`WebAuthn` virtual authenticator in the page and seeds it directly from the
vault. With `automaticPresenceSimulation` and `isUserVerified`, Chromium
signs the challenge without any human interaction.

- **Verified end to end on Authelia** (`auth.brkn.lol`, 2026-10-08, via
  the fnuc node): inject, open the login page, click "Sign in
  with a passkey", and Authelia accepts the virtual passkey as first factor
  ("Hi <name>"). Authelia's `two_factor` policy then still asks for the
  password. Never type it yourself through a browser tool (it would appear
  in your tool call): use `browser_fill_secret` when the entry is allowed
  for agents (its tool description lists them), otherwise let the user
  enter it in the live view (see [human-handoff.md](human-handoff.md)).


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
are in [counters.md](counters.md). Read it before
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
to the browser. Chromium only. The Authelia clone warning ([counters.md](counters.md)) applies here too: do
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
