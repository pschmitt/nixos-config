#!/usr/bin/env bash
# Emits the current OBS Studio status as a Go Hass Agent binary sensor.

emit_obs_sensor() {
  local state="$1"
  local icon="$2"
  local scene="$3"
  local reason="$4"

  jq -n \
    --arg icon "$icon" \
    --arg scene "$scene" \
    --arg reason "$reason" \
    --argjson state "$state" \
    '
      def attrs:
        ({ }
          | (if $scene != "" then . + {scene: $scene} else . end)
          | (if $reason != "" then . + {reason: $reason} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 10s",
          sensors: [
            (
              {
                sensor_name: "OBS",
                sensor_type: "binary",
                sensor_icon: $icon,
                sensor_state: $state
              }
              + (if ($attrs | length) > 0 then { sensor_attributes: $attrs } else {} end)
            )
          ]
        }
    '
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:video-off"
  local reason=""
  local scene=""
  local obs_bin=""

  if ! obs_bin=$(command -v obs 2>/dev/null) || [[ -z "$obs_bin" ]]
  then
    reason="OBS Studio is not installed"
    emit_obs_sensor "$state" "$icon" "$scene" "$reason"
    return
  fi

  if ! pgrep -f "$(readlink -e "$obs_bin")" >/dev/null 2>&1
  then
    reason="OBS Studio not running"
    emit_obs_sensor "$state" "$icon" "$scene" "$reason"
    return
  fi

  if ! command -v obs-cli >/dev/null 2>&1
  then
    reason="obs-cli is not installed"
    emit_obs_sensor "$state" "$icon" "$scene" "$reason"
    return
  fi

  if ! scene=$(OBS_API_HOST="${OBS_API_HOST:-localhost}" OBS_API_PORT="${OBS_API_PORT:-6277}" obs-cli -q scene current 2>/dev/null)
  then
    reason="Failed to query OBS scene"
    scene=""
  else
    state=true
    icon="mdi:video-check"
  fi

  emit_obs_sensor "$state" "$icon" "$scene" "$reason"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
