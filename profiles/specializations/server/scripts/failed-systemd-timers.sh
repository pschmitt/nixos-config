#!/usr/bin/env bash

# Check systemd timers for failed target services and surface rich diagnostics
# (state, exit code, timestamp, and recent journalctl lines).

main() {
  local timer_lines
  timer_lines=$(systemctl \
    list-timers \
    --all \
    --output=json \
    --no-pager \
    | jq -er '
      .[] | select(.last != 0) | [.unit, (.activates // "")] | @tsv
    ' 2>/dev/null || true
  )

  if [[ -z "$timer_lines" ]]; then
    echo "✅ No systemd timers found."
    exit 0
  fi

  local total_timers=0
  local failures=()

  while IFS=$'\t' read -r timer service; do
    if [[ -z "$timer" || -z "$service" ]]; then
      continue
    fi

    total_timers=$((total_timers + 1))

    local result state sub status exit_ts
    result=$(systemctl show "$service" --property=Result --value)
    state=$(systemctl show "$service" --property=ActiveState --value)

    if [[ "$result" != "success" || "$state" == "failed" ]]; then
      sub=$(systemctl show "$service" --property=SubState --value)
      status=$(systemctl show "$service" --property=ExecMainStatus --value)
      exit_ts=$(systemctl show "$service" --property=ExecMainExitTimestamp --value)

      local fail_info="• ${timer} -> ${service} (state=${state}, sub=${sub}, result=${result}"
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

      failures+=("$fail_info")
    fi
  done <<< "$timer_lines"

  if [[ ${#failures[@]} -eq 0 ]]; then
    echo "✅ All ${total_timers} active systemd timers healthy (0 failed targets detected)."
    exit 0
  fi

  echo "🚨 Failed systemd timer targets detected:"
  for failure in "${failures[@]}"; do
    printf '%s\n' "$failure"
  done
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
