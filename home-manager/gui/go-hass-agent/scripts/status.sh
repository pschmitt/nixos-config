#!/usr/bin/env bash
# Emits a binary sensor that is always on to reflect that this host is reachable.

main() {
  set -uo pipefail

  jq -n '
    {
      schedule: "@every 30s",
      sensors: [
        {
          sensor_name: "go-hass-agent Status",
          sensor_type: "binary",
          sensor_icon: "mdi:check-circle",
          sensor_device_class: "connectivity",
          sensor_state: true
        }
      ]
    }
  '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
