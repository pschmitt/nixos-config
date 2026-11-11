---
name: browser-daemon
description: Use the browser-daemon MCP for web tasks - choosing a node or saved profile, labelling the session, and managing sessions from the shell. Use before the first browser_* tool call in a conversation, or when asked to look at, stop or inspect browser sessions. For logins, passkeys, CAPTCHAs and reusing a signed-in session, use browser-login.
---

# browser-daemon

There is one browser MCP, `browser-daemon`. Browsers run on a mesh of nodes.

## Choose a browser

- Without a choice you get a fresh throwaway browser on the node with the most room.
- `browser_status` lists the nodes and the profiles you may open.
- `browser_use profile=work` opens the persistent browser-daemon profile for work web UIs (Outlook, OpsGenie). It is usually still signed in.
- `browser_use node=fnuc` opens a throwaway browser on a given node; fnuc has the home IP.
- `browser_use` closes the current browser when it switches.
- A shared profile can have tabs owned by other clients (`browser_profile_tabs`); leave those alone.

## Label your session

The dashboard shows which agent and conversation drive a session. When you start, label it with a few words, like a tmux window name, and again when the task changes:

```
browser_set_topic topic="netbox invoice lookup"
```

It works before the first page too; the label is applied once the browser connects.

## Screenshots

`browser_take_screenshot` is censored: it blacks out passwords, card and one-time-code fields, filled inputs and anything filled with `browser_fill_secret`. Use `browser_take_screenshot_unsafe` only when the censored one gets in the way of the task (you need to read a field's content); it may show credentials, so look before you pass it on. Screenshots of the user's shared desktop tabs (`browser_shared_command action=screenshot`) are censored the same way unless you pass `unsafe: true`.

## Other tools worth knowing

- `browser_ask_human` for a CAPTCHA, a device approval or anything only a person may do; navigations and clicks already report bot walls and say when to call it.
- `browser_recording` (start/stop) records your session; `browser_flight_recorder` keeps the last minute in memory and `save` keeps it when something breaks.
- `browser_network_har` (start/stop) writes the page's traffic to a HAR file with credentials redacted.
- `browser_share` makes a **public** link to your session or a recording (`expires`, default 1h); `browser_unshare` ends it. Only share when the user asks.

## Manage sessions from the shell

`browser-daemon session list|show|new|stop|rename|tabs|open`, and the same for `profile`, `recording` and `node`. Add `--json` for scripts, `--url` for another node; `browser-daemon tui` opens a terminal UI. Only stop sessions you started: others belong to other agents.

## Links to give the user

A session URL from guesswork never works. `browser_live_link` returns the live view of your current page; `browser_ask_human` builds the same link and sends it to the user (see `../browser-login/references/human-handoff.md`).

## Logins and secrets

Never read a cookie or token through a browser tool, and never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`. Load the `browser-login` skill for anything involving a login.
