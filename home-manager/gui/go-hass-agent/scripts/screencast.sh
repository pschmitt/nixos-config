#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor describing the current screencasting state tracked by the Hyprland helper.

STATE=false
ICON="mdi:monitor"
OUTPUT=""
APPS_JSON="[]"
TIMESTAMP=0
TIMESTAMP_ISO=""
STATEFILE="${TMPDIR:-/tmp}/screencast.json"

read_statefile() {
  if [[ ! -r "$STATEFILE" ]]
  then
    return 1
  fi

  local data
  if ! data=$(jq -cer '{
        state: (.state // "off"),
        output: (.output // ""),
        timestamp: (.timestamp // 0),
        apps: (.apps // [])
      }' "$STATEFILE" 2>/dev/null)
  then
    return 1
  fi

  local state_value
  state_value="$(jq -r '.state' <<<"$data")"
  OUTPUT="$(jq -r '.output' <<<"$data")"
  APPS_JSON="$(jq -c '.apps' <<<"$data")"
  TIMESTAMP="$(jq -r '.timestamp' <<<"$data")"

  if [[ "$state_value" == "on" ]]
  then
    STATE=true
    ICON="mdi:monitor-share"
  else
    STATE=false
    ICON="mdi:monitor"
  fi

  return 0
}

normalise_apps() {
  if ! jq -e 'type == "array"' <<<"$APPS_JSON" >/dev/null 2>&1
  then
    APPS_JSON="[]"
  fi
}

normalise_timestamp() {
  if [[ "$TIMESTAMP" =~ ^[0-9]+$ ]]
  then
    TIMESTAMP=$((10#$TIMESTAMP))
  else
    TIMESTAMP=0
  fi

  if (( TIMESTAMP > 0 ))
  then
    if TS=$(date -u -d "@$TIMESTAMP" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
    then
      TIMESTAMP_ISO="$TS"
    elif TS=$(date -u -r "$TIMESTAMP" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)
    then
      TIMESTAMP_ISO="$TS"
    fi
  else
    TIMESTAMP_ISO=""
  fi
}

build_attributes() {
  jq -n \
    --arg output "$OUTPUT" \
    --argjson apps "$APPS_JSON" \
    --arg last_change "$TIMESTAMP_ISO" \
    --argjson timestamp "$TIMESTAMP" \
    '
      ({}
        | (if $output != "" then . + {output: $output} else . end)
        | (if (($apps | type) == "array") and (($apps | length) > 0) then . + {apps: $apps} else . end)
        | (if $last_change != "" then . + {last_change: $last_change} else . end)
        | (if $timestamp > 0 then . + {timestamp: $timestamp} else . end)
      )
    '
}

emit_sensor() {
  local attrs_json="$1"

  jq -ner \
    --arg icon "$ICON" \
    --argjson state "$STATE" \
    --argjson attrs "$attrs_json" \
    '
      {
        schedule: "@every 5s",
        sensors: [
          (
            {
              sensor_name: "Screencast",
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

  STATE=false
  ICON="mdi:monitor"
  OUTPUT=""
  APPS_JSON="[]"
  TIMESTAMP=0
  TIMESTAMP_ISO=""

  read_statefile || true
  normalise_apps
  normalise_timestamp

  local attrs
  attrs=$(build_attributes)

  emit_sensor "$attrs"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
