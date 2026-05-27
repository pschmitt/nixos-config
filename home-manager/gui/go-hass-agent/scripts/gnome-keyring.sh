#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reflecting the GNOME Keyring unlock
# status.

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:key-chain-variant"
  local message=""

  if message=$(ECHO_NO_COLOR=1 ECHO_NO_EMOJI=1 zhj gnome-keyring::status 2>&1)
  then
    state=true
  else
    icon="mdi:key-chain"
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --arg message "$message" \
    '
      def attrs:
        ({}
          | (if $message != "" then . + {message: $message} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 30s",
          sensors: [
            (
              {
                sensor_name: "GNOME Keyring",
                sensor_type: "binary",
                sensor_icon: $icon,
                sensor_device_class: "lock",
                sensor_state: $state
              }
              + (if ($attrs | length) > 0 then { sensor_attributes: $attrs } else {} end)
            )
          ]
        }
    '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
