# When a human has to step in

Never solve or bypass a bot check yourself. If the user is willing to do it,
ask them with the MCP tool:

```text
browser_ask_human message="Solve the Google CAPTCHA, then tap Next"
```

It sends the user a link to the browser-daemon **live view of your current
page**, where they can click and type in the very session you are driving.
Say exactly what to do. Then leave the page alone, wait
(`browser_wait_for`), and take a snapshot before you continue. Whatever the
user types there (a password, a code) never passes through you. Keep the
session open meanwhile.

What happens behind it (`scripts/ask-human.sh`, which the MCP runs with the
page and node in `BD_PAGE` and `BD_NODE`):

- **Channel:** a push to the user's phone (`notify.mobile_app_pixel_11_pro`),
  or Signal (`BD_VIA=signal|both`) with the `[BROWSER HANDOFF | <AGENT>]`
  heading CONTEXT.md asks for.
- **Push expiry:** Home Assistant dismisses the phone notification after one
  hour (`timeout: 3600`, in seconds). Signal messages do not have this timeout.
- **Link:** Home Assistant says whether the user is home. Home:
  `https://browser.<node>.nb.brkn.lol/handoff/?page=<id>` (mesh only, no
  login). Away: `https://browser.<node>.brkn.lol/handoff/?page=<id>`
  (Authelia, owner only, two-factor; the vhost on rofl-10,
  `hosts/rofl-10/browserless-public.nix`, proxies only `/handoff/`,
  `/json/list` and one page's websocket).
- **The view** (`handoff.html` in browser-daemon) is made for phones: tap =
  click, drag = scroll, back/forward/reload, and a text field raises the
  phone's keyboard.

Without the MCP (another browser tool, a shell), run the script yourself:
`"$SKILL_DIR/scripts/ask-human.sh" --host NODE --page ID MESSAGE`, or
`--match REGEX` to pick the one page whose URL matches. `$SKILL_DIR` is this
skill's directory, e.g. `~/.config/claude/skills/browser-login`. `--help`
lists the other options.
