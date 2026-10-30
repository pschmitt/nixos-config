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

The MCP tells the browser-daemon dashboard which agent and conversation drive a session. When you start, label it with a few words, like a tmux window name:

```
browser-agent-topic "netbox invoice lookup"
```

Run it again when the task changes.

## Manage sessions from the shell

`browser-daemon session list|show|new|stop|rename|tabs|open`, and the same for `profile`, `recording` and `node`. Add `--json` for scripts, `--url` for another node; `browser-daemon tui` opens a terminal UI. Only stop sessions you started: others belong to other agents.

## Links to give the user

A session URL from guesswork never works. The live view of a page is
`https://browser.<node>.nb.brkn.lol/handoff/?page=<page-id>` (mesh only, no login), where
`<page-id>` is the page's `id` from `https://browser.<node>.nb.brkn.lol/json/list` and `<node>` is
the session's node (`browser-daemon session show <id>`). Away from home use `brkn.lol` instead of
`nb.brkn.lol`. `browser_ask_human` builds the link for you; see
`../browser-login/references/human-handoff.md`. Verify with `curl -fsS .../json/list` before you
send a link.

## Logins and secrets

Never read a cookie or token through a browser tool, and never type a password, token or TOTP code with `browser_type`, `browser_fill_form` or `browser_run_code_unsafe`. Load the `browser-login` skill for anything involving a login.
