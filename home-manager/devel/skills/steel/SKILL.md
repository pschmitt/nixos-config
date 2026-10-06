---
name: steel
description: >-
  Use the self-hosted Steel MCP for interactive browser sessions, JavaScript
  pages, screenshots, and browser based extraction.
---

# Steel

Use the `steel` MCP server for browser work that needs interaction or an
isolated session. It connects to the self-hosted Steel service on fnuc without
a Steel cloud account or API key.

## Choosing a tool

- Prefer `steel_scrape` for a single read-only page when it returns enough
  content without opening a browser session.
- Use `steel_session_create` with `steel_navigate`, `steel_snapshot`, and
  `steel_act` for interactive tasks. Release each session when finished;
  self-hosted Steel supports one active browser session at a time.
- Use `steel_screenshot` when a visual result is needed, then release any
  session created for it.
- The web UI is at `https://steel.fnuc.ts.brkn.lol/ui` for a person to inspect
  or take over a session.

The self-hosted Steel build does not provide CAPTCHA solving, managed proxy,
managed profiles, or credential injection. Do not claim a CAPTCHA was solved;
pause for a person to handle it. For HR WORKS, use the dedicated HR WORKS
integration worker instead of starting a second browser session through this
MCP.
