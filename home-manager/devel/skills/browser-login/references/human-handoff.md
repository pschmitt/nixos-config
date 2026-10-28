# When a human has to step in

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
