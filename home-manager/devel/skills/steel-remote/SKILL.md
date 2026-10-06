---
name: steel-remote
description: >-
  Connect the official Steel CLI or Steel MCP tools to this setup's remote,
  self-hosted Steel instances. Use when selecting fnuc, rofl-13, or rofl-14.
---

# Remote Steel instances

The official `steel-browser` skill is installed alongside this connector. The
`steel` command is a Nix-managed wrapper that targets a remote self-hosted
instance (fnuc by default). It supplies the endpoint and local placeholder API
key; do not run `steel login` for these instances. Select another host with:

```sh
steel --host fnuc scrape https://example.com
steel --host rofl-13 browser start --session task
steel --host rofl-14 browser start --session task
```

The supported hosts are `fnuc`, `rofl-13`, and `rofl-14`. Each command talks
to that host's `https://steel.<host>.ts.brkn.lol/v1` API. The existing
`steel-fnuc`, `steel-rofl-13`, and `steel-rofl-14` MCP servers target the same
instances.

For Playwright-style snapshot/ref tools (`browser_navigate`, `browser_snapshot`,
`browser_click`, `browser_run_code_unsafe`, ...) use the
`playwright-steel-fnuc`, `playwright-steel-rofl-13`, or
`playwright-steel-rofl-14` MCP servers. They attach `playwright-mcp` to the
same host's Steel over its CDP websocket (`wss://steel.<host>.ts.brkn.lol/`),
so they share that host's single browser session with the `steel-<host>` MCP
and the CLI. The browser does not persist between connections: sign in again
in each new session (use the `rbw` and `browser-passkey` skills).

The official skill's cloud login setup does not apply here. Use this wrapper
for CLI calls so they stay on the selected remote instance.

Self-hosted Steel has one concurrent browser session and does not provide
Steel Cloud's managed CAPTCHA solving, proxy, credentials, or event history.
Use `steel_session_diagnostics` with `list_live=true` to inspect MCP-owned
sessions; other event-log queries are unavailable on these instances.
