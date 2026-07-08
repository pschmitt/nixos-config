#!/usr/bin/env bash
# Emits a Go Hass Agent script sensor indicating whether pp tabs are open.

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
            sensor_name: "pp",
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
  local icon="mdi:incognito-off"

  if command -v bruvtab >/dev/null 2>&1
  then
    if bruvtab list 2>/dev/null | grep -qi 'porn'
    then
      state=true
      icon="mdi:incognito"
    fi
  fi

  emit_sensor "$icon" "$state"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
