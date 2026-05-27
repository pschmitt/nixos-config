#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor describing current lockscreen status.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

lockscreen_app() {
  local app
  for app in hyprlock swaylock gtklock
  do
    if pgrep -x "$app" >/dev/null 2>&1
    then
      echo "$app"
      return 0
    fi
  done

  return 1
}

lockscreen_state_kde_plasma() {
  dbus-send \
    --session \
    --dest=org.freedesktop.ScreenSaver \
    --type=method_call \
    --print-reply \
    /org/freedesktop/ScreenSaver org.freedesktop.ScreenSaver.GetActive 2>/dev/null \
    | grep -q 'boolean true'
}

get_display_manager() {
  local target
  if target=$(readlink "/etc/systemd/system/display-manager.service" 2>/dev/null)
  then
    target="${target##*/}"
    target="${target%.service}"
    [[ -n "$target" ]] && echo "$target"
  fi
}

main() {
  set -uo pipefail

  local state=true
  local icon="mdi:lock"
  local desktop=""
  local sensor_type="screen-lock"
  local program=""
  local error=""

  if desktop=$(guess_desktop --verify 2>/dev/null)
  then
    case "$desktop" in
      kde|KDE|plasma|Plasma)
        if lockscreen_state_kde_plasma
        then
          state=false
        fi
        program="plasma-lockscreen"
        ;;
      sway|Hyprland)
        if program=$(lockscreen_app 2>/dev/null)
        then
          state=false
        else
          program=""
        fi
        ;;
      *)
        error="Unsupported desktop: ${desktop}"
        ;;
    esac
  else
    # Assume locked when no desktop session is detected (e.g. still on greeter).
    state=false
    program="$(get_display_manager || echo "display-manager")"
    sensor_type="display-manager"
    desktop=""
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --arg type "$sensor_type" \
    --arg program "$program" \
    --arg desktop "$desktop" \
    --arg error "$error" \
    '
      def attrs:
        ({}
          | (if $type != "" then . + {type: $type} else . end)
          | (if $program != "" then . + {program: $program} else . end)
          | (if $desktop != "" then . + {desktop: $desktop} else . end)
          | (if $error != "" then . + {error: $error} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 5s",
          sensors: [
            (
              {
                sensor_name: "Lockscreen status",
                sensor_type: "binary",
                sensor_device_class: "lock",
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
