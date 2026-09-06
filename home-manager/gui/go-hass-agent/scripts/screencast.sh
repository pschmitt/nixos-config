#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor describing the current screencasting state.
#
# The state comes from screencast-state(1), which reads it out of the PipeWire
# graph the same way the pschmitt/screencast Noctalia plugin does: a live
# xdg-desktop-portal capture shows up as a PipeWire link with one endpoint on
# an xdg-desktop-portal node, and the other endpoint names the capturing
# client. That replaces the old busctl watcher
# (xdg-portal-screencast-watcher) and its /tmp/screencast.json state file, so
# nothing has to run in the background.

STATE=false
ICON="mdi:monitor"
APPS_JSON="[]"
TIMESTAMP=0
TIMESTAMP_ISO=""
# Remembers when the state last flipped, purely so the sensor can report a
# last_change attribute. It is a cache, not a source of truth: losing it only
# costs one attribute until the next change.
CACHEFILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/go-hass-agent-screencast.json"

# Names of the PipeWire clients attached to an xdg-desktop-portal node.
screencasting_apps() {
  screencast-state --json 2>/dev/null | jq -c '.apps // []'
}

read_state() {
  local apps
  if ! apps="$(screencasting_apps)" || [[ -z "$apps" ]]
  then
    return 1
  fi

  APPS_JSON="$apps"

  if jq -e 'length > 0' <<<"$APPS_JSON" >/dev/null 2>&1
  then
    STATE=true
    ICON="mdi:monitor-share"
  else
    STATE=false
    ICON="mdi:monitor"
  fi

  return 0
}

# Keep the timestamp of the last state change across invocations, so the sensor
# can report when the current screencast started or stopped.
track_change() {
  local cached_state="" cached_apps=""

  if [[ -r "$CACHEFILE" ]]
  then
    # `.state // empty` would swallow a cached `false`, so test for the key.
    cached_state="$(jq -r 'if has("state") then (.state | tostring) else "" end' "$CACHEFILE" 2>/dev/null)"
    cached_apps="$(jq -c '.apps // []' "$CACHEFILE" 2>/dev/null)"
    TIMESTAMP="$(jq -r '.timestamp // 0' "$CACHEFILE" 2>/dev/null)"
  fi

  if [[ "$cached_state" == "$STATE" ]] && [[ "$cached_apps" == "$APPS_JSON" ]]
  then
    return 0
  fi

  TIMESTAMP="$(date '+%s')"
  jq -n \
    --argjson state "$STATE" \
    --argjson apps "$APPS_JSON" \
    --argjson timestamp "$TIMESTAMP" \
    '{state: $state, apps: $apps, timestamp: $timestamp}' >"$CACHEFILE" 2>/dev/null || true
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
    --argjson apps "$APPS_JSON" \
    --arg last_change "$TIMESTAMP_ISO" \
    --argjson timestamp "$TIMESTAMP" \
    '
      ({}
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
  APPS_JSON="[]"
  TIMESTAMP=0
  TIMESTAMP_ISO=""

  read_state || true
  normalise_apps
  track_change
  normalise_timestamp

  local attrs
  attrs=$(build_attributes)

  emit_sensor "$attrs"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
