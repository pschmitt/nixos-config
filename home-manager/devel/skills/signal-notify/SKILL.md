---
name: signal-notify
description: Send the user progress updates over Signal during substantial or long-running work when they are away from the chat. Use before sending any Signal message, and when deciding whether the user can see chat updates (Home Assistant presence).
---

# Signal progress updates

## When to send

- For substantial multi-step work or long-running operations, check the user's presence in Home Assistant when it affects whether they can see chat updates. Use the HA live-context tool or `zsh -lc 'zhj hass-cli state list person'` to inspect the relevant `person.*` state. When the user is away, send concise Signal updates.
- Send for meaningful milestones, blockers that need the user's attention, and completion after a long operation. Keep routine progress in chat, avoid duplicate messages, and don't send for quick tasks.
- If Home Assistant is unavailable, continue communicating in chat.

## How to send

Prefer the `signal` MCP (`send_message` with `recipient="me"`; `list_recipients` shows the names). Fall back to Home Assistant when it is not available: `zsh -lc 'zhj hass-cli service call notify.signal_me --arguments "message=..."'`.

The MCP can also reply with a quote, react, edit and delete the bot's own messages (`send_message` returns the timestamp those need), attach files or screenshots (`attachments`), and mention people with `@{name}`. It cannot read incoming messages.

## Format

- Start every update with an uppercase ASCII task/topic and the actual harness name in `[TOPIC | HARNESS]` form on its own first line, for example `**[FNUC UPGRADE | CODEX]**`. This lets the user tell parallel agents apart; use the task topic to distinguish agents on the same harness, and don't invent a harness or agent identity.
- Then state what changed or what is blocked and the next step. Keep secrets and sensitive identifiers out of notifications.
- Both the MCP and the HA wrapper turn Markdown-ish markers into Signal styles: `**bold**`, `*italic*`, `~~strikethrough~~`, `||spoiler||`, `` `monospace` `` and fenced blocks (monospace; Signal has no real code block). Styles nest, code is literal, and a backslash escapes a marker; messages without markers remain plain. Pass `format=false` to the MCP (or `--no-format` to the sender script) to keep markup literal.
