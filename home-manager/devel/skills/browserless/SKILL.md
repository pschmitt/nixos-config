---
name: browserless
description: >-
  Use the self-hosted Browserless MCP for interactive Chromium sessions,
  JavaScript-rendered pages, screenshots, and browser based extraction.
---

# Browserless

Use the host-specific Browserless MCP that matches the browser capacity you
want. Available servers are `browserless-fnuc`, `browserless-rofl-13`, and
`browserless-rofl-14`; each connects to that host's self-hosted Chromium.

## Choosing a tool

- Prefer `browserless_smartscraper` for a single read-only page when it can
  return the needed content directly.
- Use `browserless_agent` when the task needs clicks, typing, scrolling, or
  multiple pages. Release the session when finished so the single-browser
  capacity is free for the next task.
- Use `browserless_function` only for a small, deterministic Puppeteer script
  when the higher-level tools do not fit.
- The debugger UIs are `https://browserless.<host>.ts.brkn.lol/debugger/`,
  with `fnuc`, `rofl-13`, or `rofl-14` as `<host>`.

This MCP points at the self-hosted open source Browserless instance. Account,
cloud search, and other hosted-only tools may not be available. Do not treat a
CAPTCHA as solved unless the page confirms it; this local instance does not
provide Browserless cloud CAPTCHA solving.

For HR WORKS, use the dedicated HR WORKS integration worker rather than
starting a second browser session through this MCP.
