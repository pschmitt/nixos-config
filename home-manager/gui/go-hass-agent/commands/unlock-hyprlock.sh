#!/usr/bin/env bash
# Unlocks hyprlock by sending it SIGUSR1 (immediate unlock and exit).

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

  if ! pgrep -x hyprlock >/dev/null
  then
    printf 'hyprlock is not running\n' >&2
    return 1
  fi

  pkill -SIGUSR1 -x hyprlock
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
