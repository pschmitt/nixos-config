#!/usr/bin/env bash
# Shared helpers for Go Hass Agent script sensors.

# shellcheck disable=SC2155
_guess_desktop_by_process() {
  local desktop=""

  if pgrep --exact -f "$(command -v sway 2>/dev/null)|sway" >/dev/null 2>&1
  then
    desktop="sway"
  elif pgrep --exact -f "$(command -v Hyprland 2>/dev/null)|Hyprland" >/dev/null 2>&1
  then
    desktop="Hyprland"
  fi

  [[ -n "$desktop" ]] && echo "$desktop"
}

find_sway_socket() {
  if [[ -n "${SWAYSOCK:-}" && -S "$SWAYSOCK" ]]
  then
    printf '%s\n' "$SWAYSOCK"
    return 0
  fi

  local uid="$(id -u)"
  local candidates

  if candidates=$(find "/run/user/${uid}" -maxdepth 1 -type s -name "sway-ipc.${uid}.*.sock" -printf '%T@\t%p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}') && [[ -n "$candidates" ]] && [[ -S "$candidates" ]]
  then
    printf '%s\n' "$candidates"
    return 0
  fi

  return 1
}

# shellcheck disable=SC2120
guess_desktop() {
  local verify=""

  case "${1:-}" in
    -v|--verify|-c|--check)
      verify=1
      shift
      ;;
  esac

  local desktop="${XDG_CURRENT_DESKTOP:-}"

  if [[ -n "$desktop" ]] && [[ -z "$verify" ]]
  then
    echo "$desktop"
    return 0
  fi

  if [[ -z "$desktop" ]]
  then
    desktop="$(_guess_desktop_by_process)"
  fi

  if [[ -z "$desktop" ]] && { [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || hyprctl_instance_signature >/dev/null 2>&1; }
  then
    desktop="Hyprland"
  fi

  if [[ -z "$desktop" ]] && find_sway_socket >/dev/null 2>&1
  then
    desktop="sway"
  fi

  if [[ -z "$desktop" ]]
  then
    return 1
  fi

  if [[ -n "$verify" ]]
  then
    case "$desktop" in
      sway)
        find_sway_socket >/dev/null 2>&1 || return 1
        ;;
      Hyprland)
        if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
        then
          hyprctl_instance_signature >/dev/null 2>&1 || return 1
        fi
        ;;
    esac
  fi

  echo "$desktop"
}

guess_session_type() {
  local type="${XDG_SESSION_TYPE:-}"

  if [[ -n "$type" ]]
  then
    echo "$type"
    return 0
  fi

  # shellcheck disable=SC2119
  case "$(guess_desktop 2>/dev/null)" in
    sway|Hyprland)
      type="wayland"
      ;;
  esac

  echo "$type"
}

ensure_sway_socket() {
  local swaysock
  if swaysock=$(find_sway_socket)
  then
    export SWAYSOCK="$swaysock"
    return 0
  fi

  return 1
}

swaymsg_wrapper() {
  ensure_sway_socket || return 1
  command swaymsg "$@"
}

hyprctl_instance_signature() {
  local logfile
  logfile="$(find "${TMPDIR:-/tmp}/hypr" -type f -name '*.log' -printf '%T@\t%p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')"

  if [[ -n "$logfile" ]]
  then
    basename "$(dirname "$logfile")"
  else
    return 1
  fi
}

hyprctl_wrapper() {
  if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]
  then
    local signature
    signature="$(hyprctl_instance_signature 2>/dev/null || true)"
    if [[ -n "$signature" ]]
    then
      export HYPRLAND_INSTANCE_SIGNATURE="$signature"
    fi
  fi

  command hyprctl "$@"
}
