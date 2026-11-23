#!/usr/bin/env bash
# Emits a Go Hass Agent script sensor indicating whether pp tabs are open.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

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

  if browser_tab_list | grep -qi 'porn'
  then
    state=true
    icon="mdi:incognito"
  fi

  if pgrep -f 'mpv-peepee' >/dev/null 2>&1
  then
    state=true
    icon="mdi:incognito"
  fi

  emit_sensor "$icon" "$state"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
