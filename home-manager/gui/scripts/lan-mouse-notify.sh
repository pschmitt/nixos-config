#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") {show PEER|dismiss}
EOF_USAGE
}

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$runtime_dir"
DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${runtime_dir}/bus}"
export DBUS_SESSION_BUS_ADDRESS
umask 077

notification_id_file="${runtime_dir}/lan-mouse-notification-id"
notification_lock_file="${runtime_dir}/lan-mouse-notification.lock"

ensure_runtime_dir() {
  mkdir -p "$runtime_dir"
}

close_notification() {
  local notification_id

  if [[ ! -r "$notification_id_file" ]]
  then
    return 0
  fi

  IFS= read -r notification_id < "$notification_id_file" || true
  if [[ "$notification_id" =~ ^[0-9]+$ ]]
  then
    gdbus call --session \
      --dest org.freedesktop.Notifications \
      --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification \
      "$notification_id" >/dev/null 2>&1 || true
  fi

  rm -f "$notification_id_file"
}

show_notification() {
  local peer="$1"
  local previous_id=""
  local notification_id
  local -a args

  if [[ -r "$notification_id_file" ]]
  then
    IFS= read -r previous_id < "$notification_id_file" || true
  fi

  args=(
    --app-name lan-mouse
    --icon input-mouse
    --expire-time 2500
    --print-id
  )
  if [[ "$previous_id" =~ ^[0-9]+$ ]]
  then
    args+=(--replace-id "$previous_id")
  fi

  if ! notification_id=$(notify-send "${args[@]}" "Mouse away: ${peer}")
  then
    return 0
  fi

  if [[ "$notification_id" =~ ^[0-9]+$ ]]
  then
    printf '%s\n' "$notification_id" > "$notification_id_file"
  else
    rm -f "$notification_id_file"
  fi
}

main() {
  if [[ -z "${1:-}" ]]
  then
    usage >&2
    return 2
  fi

  ensure_runtime_dir
  exec {lock_fd}> "$notification_lock_file"
  flock -x "$lock_fd"

  case "$1" in
    show)
      if [[ -z "${2:-}" ]]
      then
        printf 'Missing peer name\n' >&2
        usage >&2
        return 2
      fi
      show_notification "$2"
      ;;
    dismiss)
      close_notification
      ;;
    -h|--help)
      usage
      ;;
    *)
      printf 'Unknown action: %s\n' "$1" >&2
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
