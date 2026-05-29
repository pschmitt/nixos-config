# OpsGenie Conventions

## Access

OpsGenie EU API base URL:
- `https://api.eu.opsgenie.com/v2/`

Retrieve the API key for the relevant team:

```bash
# EDGE team
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (edge-stack)" "Atlassian (WIIT)" 2>/dev/null | tail -1)

# CKS on-call (24/7)
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (gksv3-on-call)" "Atlassian (WIIT)" 2>/dev/null | tail -1)

# CKS support (business hours)
OPSGENIE_API_KEY=$(zhj rbw::get -f "opsgenie api key (gksv3-support-schedule)" "Atlassian (WIIT)" 2>/dev/null | tail -1)
```

Use it as a GenieKey bearer in all API calls. Never commit or expose the key.

## Teams and schedules

### EDGE team

| Resource    | Value                                  |
|-------------|----------------------------------------|
| Team name   | EDGE-STACK                             |
| Team ID     | `856b67ca-9880-4632-889a-0ab28d2a31a6` |
| Schedule    | Edge Stack Schedule (`5b8e9d89-1562-4345-9441-703224afb255`) |
| Escalation  | SRE-Ops_escalation (`fc63c49d-26c7-4565-9fc8-826c63a28feb`) |

### CKS team (named GKSv3 in OpsGenie — legacy name)

**On-call (24/7)**

| Resource    | Value                                  |
|-------------|----------------------------------------|
| Team name   | GKSv3 - On-Call                        |
| Team ID     | `923da7a2-b1ab-4060-89ef-6a0394250379` |
| Schedule    | gksv3-on-call_schedule (`8aa71a67-9ddd-4571-af97-06d1ddb3c7cb`) |
| Escalation  | gksv3-on-call_escalation (`923da7a2-b1ab-4060-89ef-6a0394250379`) |

**Support (business hours)**

| Resource    | Value                                  |
|-------------|----------------------------------------|
| Team name   | GKSv3 - Support schedule - Business Hours Only |
| Schedule    | gksv3-support_schedule (`5a044893-0255-4246-8606-8e76949a861d`) |
| Escalation  | gksv3-support_escalation (`3cd62d69-3d53-4a54-ba8d-425d39893978`) |

## Common API calls

### List alerts

```bash
# Open alerts
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  "https://api.eu.opsgenie.com/v2/alerts?query=status%3Aopen&limit=50"

# Custom query (URL-encode the query string)
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  --get \
  --data-urlencode "query=status: open AND priority: P1" \
  --data-urlencode "limit=50" \
  --data-urlencode "sort=createdAt" \
  --data-urlencode "order=desc" \
  "https://api.eu.opsgenie.com/v2/alerts"
```

### Get a single alert

```bash
# By long ID
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  "https://api.eu.opsgenie.com/v2/alerts/$ALERT_ID"

# By tiny ID (short numeric id)
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  "https://api.eu.opsgenie.com/v2/alerts/$TINY_ID?identifierType=tiny"
```

### Acknowledge an alert

```bash
curl -fsSL -X POST \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"note": "Acknowledged"}' \
  "https://api.eu.opsgenie.com/v2/alerts/$ALERT_ID/acknowledge"
```

### Close an alert

```bash
curl -fsSL -X POST \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"note": "Resolved"}' \
  "https://api.eu.opsgenie.com/v2/alerts/$ALERT_ID/close"
```

### Add a note to an alert

```bash
curl -fsSL -X POST \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"note": "Your note here"}' \
  "https://api.eu.opsgenie.com/v2/alerts/$ALERT_ID/notes"
```

### Snooze an alert

End time must be an ISO 8601 timestamp (e.g. `2026-05-29T18:00:00Z`).

```bash
curl -fsSL -X POST \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"endTime": "2026-05-29T18:00:00Z"}' \
  "https://api.eu.opsgenie.com/v2/alerts/$ALERT_ID/snooze"
```

### Who is on call right now

```bash
# By schedule ID
curl -fsSL \
  -H "Authorization: GenieKey $OPSGENIE_API_KEY" \
  "https://api.eu.opsgenie.com/v2/schedules/$SCHEDULE_ID/on-calls?flat=true"
```

Or use the shell helper:

```bash
zhj opsgenie::on-duty
```

## Alert identifier types

| Type    | When to use                            |
|---------|----------------------------------------|
| `id`    | Long UUID — default                    |
| `tiny`  | Short numeric id (< 10 chars) — use `?identifierType=tiny` |
| `alias` | Custom alias set at alert creation time |

## Common query syntax

```
# Open alerts
status: open

# Open and unacknowledged
status: open AND acknowledged: false

# P1 and P2 only
priority: P1 OR priority: P2

# Alerts from the last hour
createdAt > 1h

# Filter by team tag
teams: edge-stack
```

## Safety rules

- Never commit or log API keys.
- Confirm with the user before acknowledging, closing, or snoozing alerts.
- Prefer read-only operations (list, get, on-calls) before write operations.
