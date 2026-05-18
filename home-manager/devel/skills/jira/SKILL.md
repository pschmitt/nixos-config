---
name: jira
description: Use when working with Jira at jira.wiit.one — browsing issues, running JQL searches, viewing sprint boards, kanban/on-duty boards, and reading or commenting on tickets. Read `references/conventions.md` before making changes.
---

# Jira

Use this skill for issue tracking and sprint/kanban board work on the Jira
instance at `jira.wiit.one`.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Retrieve the Jira API token:

```bash
zhj rbw::get --field 'JIRA Personal Access Token' "Atlassian (wiit.one)" 2>/dev/null | tail -1
```

3. Use the token as a Bearer token in all requests:

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/api/2/issue/CKS-123"
```

## Workflow

1. Identify whether the task involves searching, reading, or writing issues.
2. Read `references/conventions.md` to understand the project and board layout.
3. Prefer JQL searches to locate relevant issues before diving into individual
   tickets.
4. When updating or commenting on issues, confirm with the user before
   submitting.

## Reference map

- `references/conventions.md`: API access patterns, default projects, board IDs,
  and common JQL examples.

## Safety rules

- Never commit or log credentials or tokens.
- Do not delete, close, or transition issues without explicit user confirmation.
- Prefer read-only operations (search, get) before making write calls.
