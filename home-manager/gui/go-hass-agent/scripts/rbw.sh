#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reflecting the rbw unlock status.

main() {
  set -uo pipefail

  local state=false
  # NOTE cbi: requires the custom-brand-icons HACS frontend module
  local icon="cbi:bitwarden"
  local message="rbw is locked"

  if ECHO_NO_COLOR=1 ECHO_NO_EMOJI=1 rbw unlocked >/dev/null 2>&1
  then
    state=true
    message="rbw is unlocked"
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --arg message "$message" \
    '
      {
        schedule: "@every 30s",
        sensors: [
          {
            sensor_name: "rbw",
            sensor_type: "binary",
            sensor_icon: $icon,
            sensor_device_class: "lock",
            sensor_state: $state,
            sensor_attributes: {
              message: $message
            }
          }
        ]
      }
    '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
