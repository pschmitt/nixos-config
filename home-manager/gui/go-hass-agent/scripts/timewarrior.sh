#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor that reflects whether Timewarrior is currently tracking.

emit_sensor() {
  local icon="$1"
  local state="$2"

  jq -ner \
    --arg icon "$icon" \
    --argjson state "$state" \
    '
      {
        schedule: "@every 15s",
        sensors: [
          {
            sensor_name: "Timewarrior",
            sensor_type: "binary",
            sensor_icon: $icon,
            sensor_state: $state
          }
        ]
      }
    '
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:briefcase-off"

  if timew-is-on >&2
  then
    state=true
    icon="mdi:briefcase"
  fi

  emit_sensor "$icon" "$state"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
