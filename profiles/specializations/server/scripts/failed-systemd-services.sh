#!/usr/bin/env bash

# Check failed systemd services and surface rich diagnostics
# (state, exit code, timestamp, and recent journalctl lines).

main() {
  local failed_services
  failed_services=$(systemctl \
    --failed \
    --type=service \
    --output=json \
    --no-pager \
    | jq -er '
      .[] | select((.active // "") == "failed" or (.sub // "") == "failed") | .unit
    ' 2>/dev/null || true
  )

  if [[ -z "$failed_services" ]]; then
    echo "✅ All systemd services healthy (0 failed units detected)."
    exit 0
  fi

  echo "🚨 Failed systemd services detected:"
  while IFS= read -r service; do
    if [[ -z "$service" ]]; then
      continue
    fi

    local result state sub status exit_ts
    result=$(systemctl show "$service" --property=Result --value)
    state=$(systemctl show "$service" --property=ActiveState --value)
    sub=$(systemctl show "$service" --property=SubState --value)
    status=$(systemctl show "$service" --property=ExecMainStatus --value)
    exit_ts=$(systemctl show "$service" --property=ExecMainExitTimestamp --value)

    local fail_info="• ${service} (state=${state}, sub=${sub}, result=${result}"
    if [[ -n "$status" && "$status" != "0" ]]; then
      fail_info+=", exit=${status}"
    fi
    fail_info+=")"
    if [[ -n "$exit_ts" && "$exit_ts" != "0" && "$exit_ts" != "n/a" ]]; then
      fail_info+=$'\n'"  Last failure: ${exit_ts}"
    fi

    local logs
    logs=$(journalctl -u "$service" -n 8 --no-pager -o short-iso 2>&1 || true)
    if [[ -n "$logs" ]]; then
      fail_info+=$'\n'"  Recent logs:"$'\n'
      while IFS= read -r log_line; do
        fail_info+="    ${log_line}"$'\n'
      done <<< "$logs"
    fi

    printf '%s\n' "$fail_info"
  done <<< "$failed_services"

  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
