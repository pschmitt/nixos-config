#!/usr/bin/env bash
# Unlocks the active session lock screen: Noctalia (via loginctl), hyprlock
# (SIGUSR1, immediate unlock and exit), or loginctl as a generic fallback.

usage() {
  cat <<EOF
Usage: $(basename "$0")
EOF
}

main() {
  set -euo pipefail

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  local sessions=()
  while IFS= read -r s; do
    [[ -n "$s" ]] && sessions+=("$s")
  done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3 == u && $4 ~ /^seat/ {print $1}')

  local unlocked=0
  if command -v noctalia >/dev/null 2>&1 && { pgrep -x noctalia || pgrep -x .noctalia-wrapp; } >/dev/null 2>&1; then
    if [[ "$(noctalia msg status 2>/dev/null | jq -re '.locked // false')" == "true" ]]; then
      if (( ${#sessions[@]} )); then
        for s in "${sessions[@]}"; do
          loginctl unlock-session "$s"
        done
      else
        loginctl unlock-session || true
      fi
      unlocked=1
    fi
  fi

  if pgrep -x hyprlock >/dev/null 2>&1; then
    pkill -SIGUSR1 -x hyprlock
    unlocked=1
  fi

  if (( ! unlocked )); then
    # Fallback to loginctl unlock-session
    if (( ${#sessions[@]} )); then
      for s in "${sessions[@]}"; do
        loginctl unlock-session "$s" || true
      done
    else
      loginctl unlock-session || true
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
