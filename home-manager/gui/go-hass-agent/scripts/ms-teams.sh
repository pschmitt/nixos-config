#!/usr/bin/env bash
# Emits a Go Hass Agent Script Sensor (binary) for MS Teams "in a meeting".
# Requirements: `ms-teams` available in PATH.

emit_sensor() {
  local state="$1"

  jq -ner \
    --argjson state "$state" \
    '
      {
        schedule: "@every 15s",
        sensors: [
          {
            sensor_name: "MS Teams: In a meeting",
            sensor_type: "binary",
            sensor_icon: "mdi:briefcase",
            sensor_device_class: "occupancy",
            sensor_state: $state
          }
        ]
      }
    '
}

main() {
  set -u

  local state=false

  if ms-teams in-a-meeting >&2
  then
    state=true
  fi

  emit_sensor "$state"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
