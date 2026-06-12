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

# Browser Zoom tab (zoom.us/wc) -> canonical join URL, else native client.
zoom_meeting_url() {
  local burl mid
  burl="$(bruvtab list 2>/dev/null | awk -F'\t' 'index(tolower($3), "zoom.us/wc") > 0 { print $3; exit }')"
  if [[ -n "$burl" ]]
  then
    mid="$(sed -rn 's#.*/([0-9]+)/.*#\1#p' <<< "$burl")"
    if [[ -n "$mid" ]]
    then
      echo "https://zoom.us/j/${mid}"
      return 0
    fi
  fi
  if pgrep -af "zoom zoommtg://" >/dev/null 2>&1
  then
    echo "N/A (Client)"
    return 0
  fi
  return 1
}

jitsi_meeting_url() {
  local u
  u="$(bruvtab list 2>/dev/null | awk -F'\t' 'index(tolower($3), "meet.jit.si/") > 0 { print $3; exit }')"
  [[ -n "$u" ]] || return 1
  echo "$u"
}

main() {
  set -uo pipefail

  local state=false
  local provider=""
  local url=""

  if url="$(zoom_meeting_url 2>/dev/null)"
  then
    state=true
    provider="zoom"
  elif url="$(jitsi_meeting_url 2>/dev/null)"
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
