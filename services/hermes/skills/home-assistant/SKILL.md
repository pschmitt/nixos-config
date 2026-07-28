---
name: home-assistant
description: Use the configured Home Assistant MCP server and channel for smart-home inspection and control.
---

# Home Assistant

Use the `home-assistant` MCP server for Home Assistant state queries and
actions. Hermes also has a native Home Assistant channel for event-driven
interaction.

Query current state before making a change, then report the affected entity or
automation and the resulting state.

Safety rules:

- Ask for explicit confirmation before actions that affect security, entry,
  power, heating, network infrastructure, media playback, or any destructive
  or irreversible operation.
- Treat tools that run commands, restart services, update systems, or send
  messages as high impact and require explicit confirmation before calling
  them.
- Never expose access tokens, secrets, or credentials in responses.
- If Home Assistant events are needed, ask which domains or entities to watch;
  do not enable broad event monitoring by default.
