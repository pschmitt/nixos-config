---
name: n8n
description: Use when working with n8n workflows at n8n.brkn.lol — creating, editing, triggering, or inspecting workflows and executions via the MCP server.
---

# n8n

Use this skill for workflow automation tasks on the n8n instance at `n8n.brkn.lol`.

## Quick start

The n8n MCP server is pre-configured and available as `n8n-mcp`. Use MCP tools
directly to interact with workflows and executions.

## Workflow

1. List available workflows to understand what exists.
2. Inspect a workflow's nodes and connections before modifying.
3. Trigger workflows via the MCP execute tool or the n8n webhook/API.
4. Check execution results to confirm success.

## Safety rules

- Do not delete or disable workflows without explicit user confirmation.
- Prefer dry-run or test executions before triggering production workflows.
- When modifying a workflow, read the current state first.
