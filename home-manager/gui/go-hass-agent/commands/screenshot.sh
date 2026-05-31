#!/usr/bin/env bash
# Takes a screenshot via `zhj screenshot` and syncs it to the remote PiKVM share.

import_graphical_environment() {
  local key value

  while IFS='=' read -r key value
  do
    case "$key" in
      DBUS_SESSION_BUS_ADDRESS|DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|SWAYSOCK|WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP|XDG_RUNTIME_DIR|XDG_SESSION_TYPE)
        [[ -n "$value" ]] && export "$key=$value"
        ;;
    esac
  done < <(systemctl --user show-environment 2>/dev/null || true)
}

screenshot() {
  zhj screenshot "$1"
}

prune_old_screenshots() {
  [[ -z "$1" ]] && return 0
  find "$1" -type f -mtime +7 -delete
}

scp_screenshot() {
  local file="$1"
  local remote_file="${2:-$(basename "$1")}"
  scp "$file" "hv:/media/hacompanion/${remote_file}" >&2
}

main() {
  set -euo pipefail

  # SSH-triggered executions need the active user session environment to talk to Wayland.
  import_graphical_environment

  local dest="${HOME}/Pictures/Screenshots/auto"
  mkdir -p "$dest"

  local hostname="${HOSTNAME:-$(hostname)}"
  local file=""
  file="${dest}/${hostname}-$(date -Iseconds).png"

  notify-send "TOOK A SCREENSHOT"
  screenshot "$file"
  ln -sf "$file" "$dest/latest-${hostname}.png"

  local remote_file="${hostname}.png"
  scp_screenshot "$file" "$remote_file"

  prune_old_screenshots "$dest"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
