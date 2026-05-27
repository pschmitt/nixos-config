#!/usr/bin/env bash
# Emits the detected desktop environment as a Go Hass Agent script sensor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

readonly -a DESKTOP_OPTIONS=(
  "awesome"
  "budgie"
  "bspwm"
  "cinnamon"
  "cosmic"
  "deepin"
  "gnome"
  "hyprland"
  "i3wm"
  "kde-plasma"
  "leftwm"
  "lxde"
  "lxqt"
  "mate"
  "niri"
  "openbox"
  "pantheon"
  "qtile"
  "river"
  "sway"
  "wayfire"
  "xfce"
  "xmonad"
  "unknown"
)

declare -A DESKTOP_ALIASES=(
  ["awesome"]="awesome"
  ["awesomewm"]="awesome"
  ["budgie"]="budgie"
  ["budgie-gnome"]="budgie"
  ["budgiegnome"]="budgie"
  ["bspwm"]="bspwm"
  ["cinnamon"]="cinnamon"
  ["x-cinnamon"]="cinnamon"
  ["cosmic"]="cosmic"
  ["deepin"]="deepin"
  ["gnome"]="gnome"
  ["gnome-classic"]="gnome"
  ["gnomeclassic"]="gnome"
  ["gnome-flashback"]="gnome"
  ["gnomeflashback"]="gnome"
  ["gnome-shell"]="gnome"
  ["ubuntu"]="gnome"
  ["ubuntu-gnome"]="gnome"
  ["unity"]="gnome"
  ["unity7"]="gnome"
  ["x-gnome"]="gnome"
  ["pop"]="gnome"
  ["pop-os"]="gnome"
  ["popos"]="gnome"
  ["hyprland"]="hyprland"
  ["i3"]="i3wm"
  ["i3wm"]="i3wm"
  ["i3-gaps"]="i3wm"
  ["i3gaps"]="i3wm"
  ["i3withshmlog"]="i3wm"
  ["kde"]="kde-plasma"
  ["kde-plasma"]="kde-plasma"
  ["plasma"]="kde-plasma"
  ["plasma-wayland"]="kde-plasma"
  ["plasmawayland"]="kde-plasma"
  ["plasma-x11"]="kde-plasma"
  ["plasmax11"]="kde-plasma"
  ["leftwm"]="leftwm"
  ["lxde"]="lxde"
  ["lxqt"]="lxqt"
  ["mate"]="mate"
  ["niri"]="niri"
  ["openbox"]="openbox"
  ["pantheon"]="pantheon"
  ["qtile"]="qtile"
  ["river"]="river"
  ["sway"]="sway"
  ["wayfire"]="wayfire"
  ["xfce"]="xfce"
  ["xfce4"]="xfce"
  ["xfce-desktop"]="xfce"
  ["xfcedesktop"]="xfce"
  ["xmonad"]="xmonad"
)

normalize_desktop() {
  local raw_value="$1"
  [[ -z "$raw_value" ]] && return 1

  local token key collapsed
  local -a tokens=()
  IFS=':;, ' read -ra tokens <<<"$raw_value"

  for token in "${tokens[@]}"
  do
    [[ -z "$token" ]] && continue
    key="${token,,}"
    key="${key// /-}"
    key="${key//_/-}"
    key="${key//./-}"
    key="${key//+/-}"
    key="${key//--/-}"
    key="$(LC_ALL=C tr -cd '[:alnum:]-' <<<"$key")"
    key="${key//--/-}"
    key="${key#-}"
    key="${key%-}"

    if [[ -n "${DESKTOP_ALIASES[$key]:-}" ]]
    then
      printf '%s\n' "${DESKTOP_ALIASES[$key]}"
      return 0
    fi

    collapsed="${key//-/}"
    if [[ -n "$collapsed" && -n "${DESKTOP_ALIASES[$collapsed]:-}" ]]
    then
      printf '%s\n' "${DESKTOP_ALIASES[$collapsed]}"
      return 0
    fi
  done

  return 1
}

main() {
  set -uo pipefail

  local desktop="unknown"
  local error_msg=""
  local raw_desktop

  local value
  # shellcheck disable=SC2119
  if value=$(guess_desktop 2>/dev/null)
  then
    raw_desktop="$value"
    if ! desktop=$(normalize_desktop "$value")
    then
      desktop="unknown"
      error_msg="Unsupported desktop value: ${value}"
    fi
  else
    error_msg="Unable to determine desktop environment"
  fi

  local session_type
  session_type="$(guess_session_type)"

  local options_json
  options_json=$(jq -nc '$ARGS.positional' --args "${DESKTOP_OPTIONS[@]}")

  jq -n \
    --arg desktop "$desktop" \
    --arg session "$session_type" \
    --arg error "$error_msg" \
    --arg raw "$raw_desktop" \
    --argjson options "$options_json" \
    '
      def attrs:
        ({}
          | (if $session != "" then . + {session_type: $session} else . end)
          | (if $raw != "" then . + {detected_value: $raw} else . end)
          | (if $error != "" then . + {error: $error} else . end)
          | . + {options: $options}
        );

      attrs as $attrs
      | {
          schedule: "@every 3600s",
          sensors: [
            (
              {
                sensor_name: "Desktop Environment",
                sensor_type: "sensor",
                sensor_device_class: "enum",
                sensor_icon: "mdi:view-dashboard-variant",
                sensor_state: $desktop
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
