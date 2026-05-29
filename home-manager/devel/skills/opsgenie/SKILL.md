---
name: opsgenie
description: Use when working with OpsGenie — browsing alerts, checking on-call schedules, acknowledging or closing alerts, and managing incidents for the EDGE or CKS teams. Read `references/conventions.md` before making changes.
---

# OpsGenie

Use this skill for alert management and on-call work on the OpsGenie instance
used by wiit.cloud.

## Quick start

1. Read `references/conventions.md` before making changes.
2. Retrieve the API key for the relevant team:

```bash
# EDGE team
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (edge-stack)" "Atlassian (WIIT)" 2>/dev/null | tail -1)

# CKS on-call
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (gksv3-on-call)" "Atlassian (WIIT)" 2>/dev/null | tail -1)

# CKS support (business hours)
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (gksv3-support-schedule)" "Atlassian (WIIT)" 2>/dev/null | tail -1)
```

   If rbw is locked, invoke the `rbw` skill to unlock it first.

3. Use the key as a GenieKey bearer in all requests:

```bash
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  "https://api.eu.opsgenie.com/v2/alerts?query=status%3Aopen"
```

## Shell shortcut

`zhj opsgenie::alerts` queries all teams at once and renders a formatted table.
Prefer it for interactive browsing; use the raw API for scripted or structured
reads.

```bash
# Open, unacknowledged alerts across all teams
zhj opsgenie::alerts --open

# All alerts (default: status: open)
zhj opsgenie::alerts

# With alert IDs shown
zhj opsgenie::alerts --ids

# Raw JSON
zhj opsgenie::alerts --json
```

## Workflow

1. Identify the team scope (EDGE, CKS on-call, CKS support) from the task.
2. Read `references/conventions.md` for team API keys, schedule IDs, and escalation UUIDs.
3. Use `zhj opsgenie::alerts` for a quick overview before diving into individual alerts.
4. When acknowledging, closing, or adding notes to alerts, confirm with the user before submitting.

## Reference map

- `references/conventions.md`: API base URL, team API keys, schedule and
  escalation UUIDs, and common API call examples.

## Safety rules

- Never commit or log API keys.
- Do not close or delete alerts without explicit user confirmation.
- Prefer read-only operations (list, get) before making write calls.
- Acknowledge before closing — do not skip straight to resolve unless the user asks.
