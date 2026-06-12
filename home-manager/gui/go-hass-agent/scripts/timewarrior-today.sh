#!/usr/bin/env bash
# Emits a Go Hass Agent numeric sensor with the total tracked seconds in Timewarrior for today.

emit_sensor() {
  local icon="$1"
  local human="$2"
  local seconds="$3"

  jq -ner \
    --arg icon "$icon" \
    --arg human "$human" \
    --argjson seconds "$seconds" \
    '
      {
        schedule: "@every 30s",
        sensors: [
          {
            sensor_name: "Timewarrior Time Tracked Today",
            sensor_type: "sensor",
            sensor_icon: $icon,
            sensor_state: $seconds,
            sensor_device_class: "duration",
            sensor_unit_of_measurement: "s",
            sensor_attributes: { human_state: $human }
          }
        ]
      }
    '
}

main() {
  set -uo pipefail

  local seconds_total=0
  local human_state=""
  local icon="mdi:briefcase-off"

  if output=$(timew-total --seconds 2>/dev/null)
  then
    if [[ "$output" =~ ^[0-9]+$ ]]
    then
      seconds_total=$((10#$output))
    fi
  fi

  if human_output=$(timew-total 2>/dev/null)
  then
    human_state="$human_output"
  fi

  if [[ -z "$human_state" ]]
  then
    human_state="0s"
  fi

  if timew-is-on >&2
  then
    icon="mdi:briefcase"
  fi

  emit_sensor "$icon" "$human_state" "$seconds_total"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
