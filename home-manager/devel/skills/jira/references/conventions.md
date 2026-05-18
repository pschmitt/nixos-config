# Jira Conventions

## Access

Jira is available at:
- `https://jira.wiit.one`

Retrieve the API token from the password manager via `zhj`:

```bash
zhj rbw::get --field 'JIRA Personal Access Token' "Atlassian (wiit.one)" 2>/dev/null | tail -1
```

Use it as a Bearer token in all API calls:

```bash
JIRA_API_TOKEN=$(zhj rbw::get --field 'JIRA Personal Access Token' "Atlassian (wiit.one)" 2>/dev/null | tail -1)

curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/api/2/..."
```

Never commit or expose the token.

## API bases

| API            | Base URL                                    |
|----------------|---------------------------------------------|
| REST API v2    | `https://jira.wiit.one/rest/api/2/`         |
| Agile API v1   | `https://jira.wiit.one/rest/agile/1.0/`     |

## Default project and boards

| Resource              | Value                |
|-----------------------|----------------------|
| Default project       | CKS                  |
| Sprint board          | 617 (CKS Development, scrum) |
| Helpdesk/kanban board | 1200 (CKS HELPDESK, kanban) |

Sprint naming convention: `CKS Sprint YYWW` (year + calendar week, e.g. `CKS Sprint 2606`).

## Common API calls

### Search with JQL

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  --get \
  --data-urlencode "jql=project = CKS AND assignee = currentUser() AND sprint in openSprints()" \
  "https://jira.wiit.one/rest/api/2/search"
```

### Get a single issue (with changelog and comments)

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/api/2/issue/CKS-123?expand=changelog,comment"
```

### List boards for a project

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  --get \
  --data-urlencode "projectKeyOrId=CKS" \
  "https://jira.wiit.one/rest/agile/1.0/board"
```

### List active sprints for a board

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/agile/1.0/board/617/sprint?status=active"
```

### Issues in a sprint

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/agile/1.0/sprint/$SPRINT_ID/issue"
```

### Add a comment to an issue

```bash
curl -fsSL -X POST \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "Your comment here"}' \
  "https://jira.wiit.one/rest/api/2/issue/CKS-123/comment"
```

### Transition an issue (status change)

First fetch available transitions:

```bash
curl -fsSL \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  "https://jira.wiit.one/rest/api/2/issue/CKS-123/transitions"
```

Then apply one:

```bash
curl -fsSL -X POST \
  -H "Authorization: Bearer $JIRA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "31"}}' \
  "https://jira.wiit.one/rest/api/2/issue/CKS-123/transitions"
```

## Issue key format

- Keys follow `PROJECT-NUMBER` (e.g. `CKS-42`).
- Bare numbers default to the `CKS` project (e.g. `42` → `CKS-42`).
- Subtask keys are indented under their parent in board views.

## Common JQL patterns

```
# My open issues in the current sprint
project = CKS AND assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done

# All open items in the current sprint
project = CKS AND sprint in openSprints() AND statusCategory != Done ORDER BY rank ASC

# Issues flagged / impediments
project = CKS AND flagged is not EMPTY AND sprint in openSprints()

# Issues by status
project = CKS AND status = "In Progress" ORDER BY rank ASC
```

## Safety rules

- Never commit or log the API token.
- Confirm with the user before transitioning, closing, or deleting an issue.
- Prefer read-only operations before write operations.
