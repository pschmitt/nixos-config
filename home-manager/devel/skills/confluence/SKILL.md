---
name: confluence
description: Use when working with Confluence at wiki.wiit.one — searching pages, reading documentation, creating or updating pages, and navigating spaces. Read `references/conventions.md` before making changes.
---

# Confluence

Use this skill for documentation and wiki work on the Confluence instance at
`wiki.wiit.one`.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Retrieve the Confluence API token:

```bash
zhj rbw::get --field 'Confluence Personal Access Token' "Atlassian (wiit.one)" 2>/dev/null | tail -1
```

3. Use the token as a Bearer token in all requests:

```bash
curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  "https://wiki.wiit.one/rest/api/content/12345"
```

## Workflow

1. Identify the target space (`CKS`, `edge`, etc.) from the task context.
2. Read `references/conventions.md` for space keys and CQL patterns.
3. Search for existing pages before creating new ones.
4. When creating or updating pages, confirm the target space and parent page
   with the user before writing.

## Reference map

- `references/conventions.md`: API access, relevant spaces, CQL search
  patterns, and page create/update examples.

## Safety rules

- Never commit or log credentials or tokens.
- Do not delete pages without explicit user confirmation.
- Prefer reading and searching before making write calls.
- When updating a page, always fetch the current version number first — the
  update API requires it.
