#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor describing whether an online meeting is ongoing
# and, when possible, exposes the provider/URL as attributes. Mirrors the old
# hacompanion online-meeting.sh helper.

emit_sensor() {
  local state="$1"
  local provider="$2"
  local url="$3"

  jq -n \
    --argjson state "$state" \
    --arg provider "$provider" \
    --arg url "$url" \
    '
      def attrs:
        ({}
          | (if $provider != "" then . + {provider: $provider} else . end)
          | (if $url != "" then . + {url: $url} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 15s",
          sensors: [
            (
              {
                sensor_name: "Online meeting",
                sensor_type: "binary",
                sensor_icon: "mdi:video",
                sensor_device_class: "occupancy",
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
  local provider=""
  local url=""

  if url="$(zhj zoom::meeting-url 2>/dev/null)"
  then
    state=true
    provider="zoom"
  elif url="$(zhj jitsi::meeting-url 2>/dev/null)"
  then
    state=true
    provider="jitsi"
  elif ms-teams in-a-meeting >/dev/null 2>&1
  then
    state=true
    provider="msteams"
  fi

  emit_sensor "$state" "$provider" "$url"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
