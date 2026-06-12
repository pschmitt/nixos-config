#!/usr/bin/env bash
# Emits monitor information (count and metadata) as a Go Hass Agent script sensor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

STATE=0
ICON="mdi:monitor"
ERROR=""
MONITORS_JSON="[]"
SESSION=""
DESKTOP=""

collect_wayland_sway() {
  local data
  if ! data=$(swaymsg_wrapper --raw --type get_outputs 2>/dev/null)
  then
    ERROR="Failed to query sway outputs"
    return 1
  fi

  MONITORS_JSON=$(jq -cer '[.[] | select(.active == true) | {
      name: .name,
      make: .make,
      model: .model,
      width: (.current_mode.width // .rect.width),
      height: (.current_mode.height // .rect.height),
      refresh: (.current_mode.refresh // null),
      scale: (.scale // 1)
    }]' <<<"$data" 2>/dev/null || echo "[]")
  return 0
}

collect_wayland_hyprland() {
  local data
  if ! data=$(hyprctl_wrapper -j monitors 2>/dev/null)
  then
    ERROR="Failed to query Hyprland monitors"
    return 1
  fi

  MONITORS_JSON=$(jq -cer '[.[] | {
      name: .name,
      make: .make,
      model: .model,
      width: .width,
      height: .height,
      refresh: (.refreshRate // null),
      scale: (.scale // 1),
      focused: (.focused // false)
    }]' <<<"$data" 2>/dev/null || echo "[]")
  return 0
}

collect_xorg() {
  local info
  if ! info=$(xrandr --listactivemonitors 2>/dev/null)
  then
    ERROR="xrandr unavailable"
    return 1
  fi

  local text
  text="$(awk '/^\s+[0-9]+:/ { sub(/^\s+/, ""); print }' <<<"$info")"
  MONITORS_JSON=$(jq -Rs 'split("\n") | map(select(length > 0))' <<<"$text")
  return 0
}

main() {
  set -uo pipefail

  STATE=0
  ICON="mdi:monitor"
  ERROR=""
  MONITORS_JSON="[]"
  SESSION="$(guess_session_type 2>/dev/null)"
  DESKTOP="$(guess_desktop 2>/dev/null || true)"

  case "$SESSION" in
    wayland)
      local handled=0

      if [[ "$DESKTOP" == "sway" || -z "$DESKTOP" ]]
      then
        if collect_wayland_sway
        then
          handled=1
          ERROR=""
        fi
      fi

      if (( handled == 0 )) && [[ "$DESKTOP" == "Hyprland" || -z "$DESKTOP" ]]
      then
        if collect_wayland_hyprland
        then
          handled=1
          ERROR=""
        fi
      fi

      if (( handled == 0 )) && [[ -z "$ERROR" ]]
      then
        if [[ -z "$DESKTOP" ]]
        then
          ERROR="Unable to determine Wayland compositor"
        else
          ERROR="Unsupported Wayland desktop: ${DESKTOP}"
        fi
      fi
      ;;
    "")
      ERROR="Session type unknown"
      ;;
    *)
      if collect_xorg
      then
        ERROR=""
      fi
      ;;
  esac

  STATE=$(jq -er 'length' <<<"$MONITORS_JSON" 2>/dev/null || echo 0)
  if [[ ! "$STATE" =~ ^[0-9]+$ ]]
  then
    STATE=0
  fi

  if (( STATE == 0 ))
  then
    ICON="mdi:monitor-off"
  elif (( STATE > 1 ))
  then
    ICON="mdi:monitor-multiple"
  fi

  jq -n \
    --arg icon "$ICON" \
    --argjson state "$STATE" \
    --arg desktop "$DESKTOP" \
    --arg session "$SESSION" \
    --arg error "$ERROR" \
    --argjson monitors "$MONITORS_JSON" \
    '
      def attrs:
        ({}
          | (if $desktop != "" then . + {desktop: $desktop} else . end)
          | (if $session != "" then . + {session_type: $session} else . end)
          | (if $error != "" then . + {error: $error} else . end)
          | (if ($monitors | length) > 0 then . + {monitors: $monitors} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 30s",
          sensors: [
            (
              {
                sensor_name: "Monitors",
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
