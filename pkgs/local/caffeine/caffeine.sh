#!/usr/bin/env bash
# Control Noctalia's idle inhibitor (caffeine).

usage() {
  cat <<EOF
Usage: $(basename "$0") [ACTION] [OPTIONS]

Control Noctalia's idle inhibitor (caffeine).

Actions:
  status, is-on       Show current caffeine status (default if no action given)
  toggle              Toggle caffeine on/off
  on, enable          Enable caffeine
  off, disable        Disable caffeine
  for DURATION        Enable caffeine for a duration (e.g. 30m, 1h, 45s)
  run, exec CMD...    Run a command with caffeine enabled

Options:
  -q, --quiet         Suppress output (status exits 0 if enabled, 1 if disabled)
  -c, --check         Exit 0 if enabled, 1 if disabled (without output unless requested)
  -s, --status        Show status
  -j, --json          Output status as JSON: {"enabled": bool}
  -h, --help          Show this help
EOF
}

find_noctalia_socket() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  local sock

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]
  then
    sock="${runtime_dir}/noctalia-${WAYLAND_DISPLAY}.sock"
    if [[ -S "$sock" ]]
    then
      return 0
    fi
  fi

  for sock in "${runtime_dir}"/noctalia-wayland-*.sock
  do
    if [[ -S "$sock" ]]
    then
      local target="${sock##*noctalia-}"
      export WAYLAND_DISPLAY="${target%.sock}"
      return 0
    fi
  done

  for sock in "${runtime_dir}"/noctalia-*.sock
  do
    if [[ -S "$sock" ]]
    then
      if [[ "$sock" == *dmenu* ]]
      then
        continue
      fi
      local target="${sock##*noctalia-}"
      export WAYLAND_DISPLAY="${target%.sock}"
      return 0
    fi
  done

  return 1
}

ensure_noctalia() {
  if ! command -v noctalia >/dev/null 2>&1
  then
    printf 'Error: noctalia command not found\n' >&2
    return 1
  fi

  if ! find_noctalia_socket
  then
    printf 'Error: Noctalia is not running (socket not found)\n' >&2
    return 1
  fi

  if ! noctalia msg status >/dev/null 2>&1
  then
    printf 'Error: Noctalia is not responding\n' >&2
    return 1
  fi

  return 0
}

notify_battery_icon() {
  noctalia msg plugin "pschmitt/battery-icon:poller" all refresh >/dev/null 2>&1 || true
}

is_caffeine_active() {
  local uid
  uid="$(id -u)"
  systemd-inhibit --list --json=short | jq -e --arg uid "$uid" \
    '.[] | select(.uid == ($uid | tonumber) and .who == "noctalia" and (.what | test("idle")))' >/dev/null 2>&1
}

caffeine_on() {
  local quiet="${1:-}"

  ensure_noctalia || return 1
  noctalia msg caffeine-enable >/dev/null
  notify_battery_icon
  if [[ -z "$quiet" ]]
  then
    printf 'Caffeine enabled\n'
  fi
}

caffeine_off() {
  local quiet="${1:-}"

  ensure_noctalia || return 1
  noctalia msg caffeine-disable >/dev/null
  notify_battery_icon
  if [[ -z "$quiet" ]]
  then
    printf 'Caffeine disabled\n'
  fi
}

caffeine_toggle() {
  local quiet="${1:-}"

  ensure_noctalia || return 1
  noctalia msg caffeine-toggle >/dev/null
  notify_battery_icon
  if is_caffeine_active
  then
    if [[ -z "$quiet" ]]
    then
      printf 'Caffeine enabled\n'
    fi
  else
    if [[ -z "$quiet" ]]
    then
      printf 'Caffeine disabled\n'
    fi
  fi
  return 0
}

caffeine_status() {
  local quiet="${1:-}"
  local format="${2:-}"
  local check_only="${3:-}"

  ensure_noctalia || return 1
  if is_caffeine_active
  then
    if [[ "$format" == "json" ]]
    then
      printf '{"enabled":true}\n'
    elif [[ -z "$quiet" ]]
    then
      printf 'enabled\n'
    fi
    return 0
  else
    if [[ "$format" == "json" ]]
    then
      printf '{"enabled":false}\n'
    elif [[ -z "$quiet" ]]
    then
      printf 'disabled\n'
    fi
    if [[ -n "$quiet" || -n "$check_only" ]]
    then
      return 1
    fi
    return 0
  fi
}

caffeine_run() {
  ensure_noctalia || return 1
  local was_active=""

  if is_caffeine_active
  then
    was_active=1
  fi

  if [[ -z "$was_active" ]]
  then
    noctalia msg caffeine-enable >/dev/null
    notify_battery_icon
    trap 'noctalia msg caffeine-disable >/dev/null 2>&1; notify_battery_icon' EXIT INT TERM
  fi

  "$@"
  local rc=$?

  if [[ -z "$was_active" ]]
  then
    trap - EXIT INT TERM
    noctalia msg caffeine-disable >/dev/null 2>&1
    notify_battery_icon
  fi

  return "$rc"
}

caffeine_for() {
  local duration="${1:-}"
  local rc

  if [[ -z "$duration" ]]
  then
    printf 'Missing duration (e.g. 30m, 1h)\n' >&2
    return 2
  fi

  printf 'Caffeine enabled for %s...\n' "$duration"
  caffeine_run sleep "$duration"
  rc=$?
  if [[ "$rc" -eq 0 ]]
  then
    printf 'Caffeine expired\n'
  fi
  return "$rc"
}

main() {
  local quiet=""
  local format=""
  local action="status"
  local check_only=""
  local -a cmd_args=()

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -q|--quiet)
        quiet=1
        shift
        ;;
      -c|--check)
        action="status"
        check_only=1
        shift
        ;;
      -j|--json)
        format="json"
        action="status"
        shift
        ;;
      -s|--status)
        action="status"
        shift
        ;;
      on|enable|start)
        action="on"
        shift
        ;;
      off|disable|stop)
        action="off"
        shift
        ;;
      toggle)
        action="toggle"
        shift
        ;;
      status)
        action="status"
        shift
        ;;
      is-on|check)
        action="status"
        check_only=1
        shift
        ;;
      for)
        action="for"
        shift
        if [[ -z "${1:-}" ]]
        then
          printf 'Missing duration for "for" action (e.g. 30m, 1h)\n' >&2
          usage >&2
          return 2
        fi
        cmd_args+=("$1")
        shift
        ;;
      [0-9]*s|[0-9]*m|[0-9]*h|[0-9]*d|[0-9]*)
        action="for"
        cmd_args+=("$1")
        shift
        ;;
      run|exec)
        action="run"
        shift
        if [[ -z "${1:-}" ]]
        then
          printf 'Missing command to run\n' >&2
          usage >&2
          return 2
        fi
        cmd_args+=("$@")
        break
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  case "$action" in
    on)
      caffeine_on "${quiet:-}"
      ;;
    off)
      caffeine_off "${quiet:-}"
      ;;
    toggle)
      caffeine_toggle "${quiet:-}"
      ;;
    status)
      caffeine_status "${quiet:-}" "${format:-}" "${check_only:-}"
      ;;
    for)
      caffeine_for "${cmd_args[@]+"${cmd_args[@]}"}"
      ;;
    run)
      caffeine_run "${cmd_args[@]+"${cmd_args[@]}"}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
