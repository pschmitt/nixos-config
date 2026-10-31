#!/usr/bin/env bash
# Health check script for teams-live service

if ! systemctl is-active --quiet teams-live.service; then
  echo "teams-live.service is not active" >&2
  exit 1
fi

if journalctl -u teams-live.service --since "5 minutes ago" --no-pager | grep -q "Fatal error in teams-live"; then
  echo "teams-live encountered a fatal error in the last 5m" >&2
  exit 2
fi

logs="$(journalctl -u teams-live.service --since "10 minutes ago" --no-pager)"
if echo "$logs" | grep -q "ACTION REQUIRED"; then
  last_fail="$(echo "$logs" | grep -n "ACTION REQUIRED" | tail -1 | cut -d: -f1)"
  last_success="$(echo "$logs" | grep -n "Sign-in via browser-daemon succeeded" | tail -1 | cut -d: -f1)"
  if [ -n "$last_fail" ] && { [ -z "$last_success" ] || [ "$last_fail" -gt "$last_success" ]; }; then
    echo "teams-live has an unresolved browser-daemon auth failure" >&2
    exit 3
  fi
fi

echo "teams-live is healthy"
exit 0
