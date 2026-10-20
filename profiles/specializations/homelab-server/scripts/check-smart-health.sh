#!/usr/bin/env bash

check_device() {
  local device="$1"
  local device_type="$2"
  local health_json
  local smartctl_status

  if health_json=$(smartctl --json --health --device="$device_type" "$device")
  then
    smartctl_status=0
  else
    smartctl_status=$?
  fi

  if [[ "$smartctl_status" -eq 0 ]] && jq -e '.smart_status.passed == true' <<< "$health_json" >/dev/null
  then
    printf 'SMART health passed: %s (%s)\n' "$device" "$device_type"
    return 0
  fi

  printf 'SMART health check failed: %s (%s)\n%s\n' "$device" "$device_type" "$health_json" >&2
  return 1
}

main() {
  local scan_json
  local device_count=0
  local failures=0
  local device_entry
  local device
  local device_type

  if ! scan_json=$(smartctl --json --scan-open)
  then
    printf 'Failed to scan for SMART devices:\n%s\n' "$scan_json" >&2
    return 1
  fi

  if ! jq -e '.devices | length > 0' <<< "$scan_json" >/dev/null
  then
    printf 'No SMART-capable devices found\n' >&2
    return 1
  fi

  while IFS= read -r device_entry
  do
    IFS=$'\t' read -r device device_type <<< "$device_entry"
    device_count=$((device_count + 1))

    if ! check_device "$device" "$device_type"
    then
      failures=$((failures + 1))
    fi
  done < <(jq -r '.devices[] | [.name, .type] | @tsv' <<< "$scan_json")

  if [[ "$device_count" -eq 0 ]]
  then
    printf 'No SMART-capable devices found\n' >&2
    return 1
  fi

  if [[ "$failures" -gt 0 ]]
  then
    printf '%s of %s SMART device checks failed\n' "$failures" "$device_count" >&2
    return 1
  fi

  printf 'SMART health passed for %s device(s)\n' "$device_count"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
