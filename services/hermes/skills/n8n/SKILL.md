---
name: n8n
description: Manage workflows on n8n.brkn.lol through the configured n8n MCP server.
---

# n8n

Use the `n8n` MCP server for workflow discovery, inspection, validation, and
changes. It is already authenticated to `n8n.brkn.lol`.

Start by searching for a workflow and inspecting its details. Before changing
one, explain the intended change and validate the result.

Use the tools exposed by this server, such as `search_workflows`,
`get_workflow_details`, `search_nodes`, `validate_node_config`,
`validate_workflow`, and `create_workflow_from_code`.

Safety rules:

- Do not create, update, publish, unpublish, archive, restore, or execute a
  workflow without the user's explicit confirmation.
- Do not inspect or modify credentials unless the user explicitly requests it.
- Prefer validation and test data before a production execution.
- Report a workflow ID, whether it is published, and the validation outcome
  after every change.
