#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reporting bluetooth service status and connected devices.

bluetooth_devices() {
  bluetoothctl devices Connected 2>/dev/null \
    | jc --bluetoothctl 2>/dev/null \
    | jq -r '
        .[]
        | select(.address != null)
        | (
            if ((.alias // "") | length) > 0 then .alias
            elif ((.name // "") | length) > 0 then .name
            else "unknown"
            end
          ) as $name
        | "\(.address) (\($name))"
      '
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:bluetooth-off"
  local devices_json='[]'

  if systemctl is-active --quiet bluetooth 2>/dev/null
  then
    state=true
    icon="mdi:bluetooth"
    local devices=()
    while IFS= read -r line
    do
      [[ -n "$line" ]] && devices+=("$line")
    done < <(bluetooth_devices)

    if (( ${#devices[@]} > 0 ))
    then
      devices_json="$(printf '%s\n' "${devices[@]}" | jq -R . | jq -s -c)"
    fi
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --argjson devices "$devices_json" \
    '
      def attrs:
        ({}
          | . + {devices: $devices}
        );

      attrs as $attrs
      | {
          schedule: "@every 30s",
          sensors: [
            (
              {
                sensor_name: "Bluetooth status",
                sensor_type: "binary",
                sensor_device_class: "connectivity",
                sensor_icon: $icon,
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
