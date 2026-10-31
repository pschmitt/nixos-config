#!/usr/bin/env bash
# Health check script for teams-live service

if ! systemctl is-active --quiet teams-live.service; then
  echo "teams-live.service is not active" >&2
  exit 1
fi

HEALTH_FILE="/var/lib/teams-live/state/health.json"

if [ ! -f "$HEALTH_FILE" ]; then
  echo "teams-live health.json does not exist yet" >&2
  exit 2
fi

now="$(date +%s)"
mtime="$(stat -c %Y "$HEALTH_FILE")"
age=$(( now - mtime ))

if [ "$age" -gt 90 ]; then
  echo "teams-live health.json is stale (${age}s old, limit: 90s)" >&2
  exit 3
fi

status="$(jq -r '.status // "unknown"' "$HEALTH_FILE")"
if [ "$status" = "starting" ]; then
  uptime="$(jq -r '.uptime_seconds // 0' "$HEALTH_FILE")"
  echo "teams-live is starting up (${uptime}s)"
  exit 0
fi

if [ "$status" = "unhealthy" ]; then
  uptime="$(jq -r '.uptime_seconds // 0' "$HEALTH_FILE")"
  if [ "$uptime" -lt 45 ]; then
    echo "teams-live is in startup grace period (${uptime}s)"
    exit 0
  fi
  errors="$(jq -r '(.errors // []) | join(", ")' "$HEALTH_FILE")"
  echo "teams-live is unhealthy: ${errors:-unknown error}" >&2
  exit 4
fi

if [ "$status" = "degraded" ]; then
  errors="$(jq -r '(.errors // []) | join(", ")' "$HEALTH_FILE")"
  echo "teams-live is degraded: ${errors:-unknown issue}"
  exit 0
fi

echo "teams-live is healthy (${status})"
exit 0
