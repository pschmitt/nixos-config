#!/usr/bin/env bash
# Emits a binary sensor indicating whether the PiKVM is connected.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

check_hid() {
  lsusb -d 1a40:0101 >/dev/null 2>&1
}

check_display_sway() {
  swaymsg_wrapper --raw --type get_outputs --pretty 2>/dev/null | grep -qi pikvm
}

check_display_hyprland() {
  hyprctl_wrapper -j monitors 2>/dev/null | jq -e 'map(.description // "" | test("pikvm"; "i")) | any' >/dev/null 2>&1
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:keyboard-off"
  local hid_present=false
  local display_present=false
  local error_msg=""

  if check_hid
  then
    hid_present=true
  fi

  local desktop
  desktop="$(guess_desktop 2>/dev/null || true)"

  case "$desktop" in
    sway)
      if check_display_sway
      then
        display_present=true
      fi
      ;;
    Hyprland)
      if check_display_hyprland
      then
        display_present=true
      fi
      ;;
    "")
      error_msg="Desktop undetected"
      ;;
    *)
      error_msg="Unsupported desktop: ${desktop}"
      ;;
  esac

  if [[ "$hid_present" == true ]] || [[ "$display_present" == true ]]
  then
    state=true
  fi

  if [[ "$hid_present" == true ]]
  then
    icon="mdi:keyboard"
  elif [[ "$display_present" == true ]]
  then
    icon="mdi:monitor"
  else
    icon="mdi:keyboard-off"
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --argjson hid "$hid_present" \
    --argjson display "$display_present" \
    --arg desktop "$desktop" \
    --arg error "$error_msg" \
    '
      def attrs:
        ({
          hid_connected: $hid,
          display_connected: $display
        }
          | (if $desktop != "" then . + {desktop: $desktop} else . end)
          | (if $error != "" then . + {error: $error} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 30s",
          sensors: [
            (
              {
                sensor_name: "PiKVM connected",
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
