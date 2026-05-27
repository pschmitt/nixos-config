#!/usr/bin/env bash
# Emits the current timestamp as a Go Hass Agent script sensor so Home Assistant
# can track when this workstation was last seen.

main() {
  set -uo pipefail

  local timestamp
  timestamp="$(date -Iseconds)"

  jq -n \
    --arg timestamp "$timestamp" \
    '
      {
        schedule: "@every 30s",
        sensors: [
          {
            sensor_name: "go-hass-agent Last seen",
            sensor_icon: "mdi:clock",
            sensor_device_class: "timestamp",
            sensor_state: $timestamp
          }
        ]
      }
    '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
