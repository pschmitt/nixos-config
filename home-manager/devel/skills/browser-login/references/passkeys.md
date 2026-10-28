# Passkeys in automated browsers

The remote browsers have no security key and no platform authenticator.
`browser_passkey` arms your browser instead: for a few minutes (`minutes`,
default 5, at most 30; `0` stops) every passkey request of its pages on the
allowed sites is signed from the vault by the node's secret agent
(`rbw passkey assert`) and answered in the page. Nothing secret reaches you.

1. Open the sign-in page.
2. Call `browser_passkey` (with `site=` when you know it, e.g.
   `microsoft.com`). Its tool description lists the sites open to agents.
3. Click the site's passkey sign-in, or continue the flow that asks for it.
   Requests on page load and across origins (Microsoft's
   `login.microsoft.com/common/bridge/fido`) are answered too.
4. Take a snapshot to check that the site accepted the sign-in: a signed
   assertion does not prove that.

When it does not work:

- **The vault is locked:** the secret agent asks the user's phone first;
  the page waits up to five minutes.
- **The site is not allowed:** the tool says so. Hand the sign-in to the user
  ([human-handoff.md](human-handoff.md)).
- **No passkey, or several:** the page falls back to the browser's own prompt,
  which a remote browser cannot answer. Ask the user.
- **Firefox sessions:** not supported; use a Chromium session.

Autofill (conditional) passkey requests are left to the browser.

## Counters and clone warnings

Every assertion advances the passkey's counter in the vault. A Bitwarden
client that signs in to the same site with the same passkey and an older
counter may be rejected as a clone. This happened with Authelia
(`auth.brkn.lol`), which is why it is not open to agents. See
[counters.md](counters.md) before you change a counter or repair a site.

## Passkeys in the live view (a human signing in)

When a person signs in through the live view (`browser_ask_human`), a passkey
request they start there gets a prompt in the view: it shows whether rbw is
locked and which vault entry would sign in, with a picker when several match.
Approving has the secret agent sign it. A request that did not follow input
in the view within 15 s goes to the page's normal path, so an armed
`browser_passkey` keeps working while a person watches.
