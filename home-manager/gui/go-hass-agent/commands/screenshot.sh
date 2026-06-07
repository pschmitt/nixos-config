#!/usr/bin/env bash
# Takes a screenshot via grim and syncs it to the remote PiKVM share.

usage() {
  cat <<EOF
Usage: $(basename "$0") [--notify]
EOF
}

import_user_environment() {
  local line

  while IFS= read -r line
  do
    [[ -z "$line" || "$line" == PATH=* ]] && continue
    export "${line?}"
  done < <(systemctl --user show-environment 2>/dev/null || true)
}

screenshot() {
  grim "$1"
}

prune_old_screenshots() {
  [[ -z "$1" ]] && return 0
  find "$1" -type f -mtime +7 -delete
}

scp_screenshot() {
  local file="$1"
  local remote_file="${2:-$(basename "$1")}"
  ssh -o BatchMode=yes hv "mkdir -p /media/go-hass-agent" >&2
  scp "$file" "hv:/media/go-hass-agent/${remote_file}" >&2
}

main() {
  set -euo pipefail
  local notify=""

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -n|--notify)
        notify=1
        shift
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  # SSH-triggered executions need the active user session environment to talk to Wayland.
  import_user_environment

  local dest="${HOME}/Pictures/Screenshots/auto"
  mkdir -p "$dest"

  local hostname="${HOSTNAME:-$(hostname)}"
  local file=""
  file="${dest}/${hostname}-$(date -Iseconds).png"

  screenshot "$file"
  if [[ -n "${notify}" ]]
  then
    notify-send "Screenshot saved"
  fi
  ln -sf "$file" "$dest/latest-${hostname}.png"

  local remote_file="${hostname}.png"
  scp_screenshot "$file" "$remote_file"

  prune_old_screenshots "$dest"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
