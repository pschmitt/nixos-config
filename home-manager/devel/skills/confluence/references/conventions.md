# Confluence Conventions

## Access

Confluence is available at:
- `https://wiki.wiit.one`

Retrieve the API token:

```bash
CONFLUENCE_API_TOKEN=$(zhj rbw::get --field 'Confluence Personal Access Token' "Atlassian (wiit.one)" 2>/dev/null | tail -1)
```

Use it as a Bearer token in all API calls. Never commit or expose the token.

## API

Only the REST API v1 is available:

| Resource   | Base URL                              |
|------------|---------------------------------------|
| Content    | `https://wiki.wiit.one/rest/api/content` |
| Search     | `https://wiki.wiit.one/rest/api/content/search` |
| Spaces     | `https://wiki.wiit.one/rest/api/space` |

There is no v2 API (`/api/v2/`) on this instance.

## Relevant spaces

| Key    | Name                              | Notes                    |
|--------|-----------------------------------|--------------------------|
| `CKS`  | Cloud Kubernetes Service          | Primary team space       |
| `edge` | Wiit Edge                         | EDGE team space          |
| `CPES` | Cloud Platform & Edge Services    | Related platform space   |
| `SUP`  | Cloud & Edge Support-Dokumentation| Support docs             |
| `KD`   | Knowledge Database                | General company KB       |
| `DEV`  | Development                       | Cross-team dev docs      |

Personal spaces use the key `~username` (e.g. `~pschmitt`).

## Common API calls

### Search with CQL

```bash
curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  --get \
  --data-urlencode 'cql=space = CKS AND type = page AND text ~ "kubernetes" ORDER BY lastmodified DESC' \
  --data-urlencode 'limit=25' \
  --data-urlencode 'expand=space,version' \
  "https://wiki.wiit.one/rest/api/content/search"
```

### Get a page by ID

```bash
curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  "https://wiki.wiit.one/rest/api/content/12345?expand=body.storage,version,ancestors"
```

### Get a page by space key and title

```bash
curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  --get \
  --data-urlencode 'spaceKey=CKS' \
  --data-urlencode 'title=My Page Title' \
  --data-urlencode 'expand=body.storage,version' \
  "https://wiki.wiit.one/rest/api/content"
```

### List child pages

```bash
curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  "https://wiki.wiit.one/rest/api/content/12345/child/page"
```

### Create a new page

```bash
curl -fsSL -X POST \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "page",
    "title": "My New Page",
    "space": {"key": "CKS"},
    "ancestors": [{"id": "PARENT_PAGE_ID"}],
    "body": {
      "storage": {
        "value": "<p>Page content in Confluence Storage Format (XHTML).</p>",
        "representation": "storage"
      }
    }
  }' \
  "https://wiki.wiit.one/rest/api/content"
```

### Update an existing page

Always fetch the current version number first, then increment it by 1:

```bash
# 1. Get current version
VERSION=$(curl -fsSL \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  "https://wiki.wiit.one/rest/api/content/12345" | jq '.version.number')

# 2. Update with version + 1
curl -fsSL -X PUT \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"page\",
    \"title\": \"My Updated Page\",
    \"version\": {\"number\": $((VERSION + 1))},
    \"body\": {
      \"storage\": {
        \"value\": \"<p>Updated content.</p>\",
        \"representation\": \"storage\"
      }
    }
  }" \
  "https://wiki.wiit.one/rest/api/content/12345"
```

### Add a comment to a page

```bash
curl -fsSL -X POST \
  -H "Authorization: Bearer $CONFLUENCE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "comment",
    "container": {"id": "12345", "type": "page"},
    "body": {
      "storage": {
        "value": "<p>Comment text here.</p>",
        "representation": "storage"
      }
    }
  }' \
  "https://wiki.wiit.one/rest/api/content"
```

## Common CQL patterns

```
# Recent pages in CKS space
space = CKS AND type = page ORDER BY lastmodified DESC

# Pages I recently modified
space in (CKS, edge) AND type = page AND creator = currentUser() ORDER BY lastmodified DESC

# Full-text search across my main spaces
space in (CKS, edge) AND type = page AND text ~ "search term"

# Pages in a specific space with a label
space = CKS AND type = page AND label = "runbook"

# Pages modified in the last 7 days
space = CKS AND type = page AND lastModified >= now("-7d")
```

## Content format

Page bodies use **Confluence Storage Format** (a subset of XHTML). Key tags:

```xml
<p>Paragraph</p>
<h1>Heading 1</h1>
<ul><li>List item</li></ul>
<ol><li>Ordered item</li></ol>
<code>inline code</code>
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">bash</ac:parameter>
  <ac:plain-text-body><![CDATA[echo hello]]></ac:plain-text-body>
</ac:structured-macro>
```

## Safety rules

- Never commit or log the API token.
- Do not delete pages without explicit user confirmation.
- Always fetch the current version number before updating a page.
- Prefer CQL search to locate existing pages before creating duplicates.
