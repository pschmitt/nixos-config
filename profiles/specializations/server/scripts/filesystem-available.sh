#!/usr/bin/env bash

usage() {
  printf 'Usage: %s MOUNTPOINT [MINIMUM_PERCENT]\n' "$(basename "$0")"
}

main() {
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]
  then
    usage
    return 0
  fi
  if (( $# < 1 || $# > 2 ))
  then
    usage >&2
    return 2
  fi

  local mountpoint="$1"
  local minimum="${2:-10}"
  local report total available
  if [[ ! "$minimum" =~ ^[0-9]+$ ]] || (( minimum > 100 ))
  then
    printf 'Invalid minimum percentage\n' >&2
    return 2
  fi
  report="$(timeout 10s df -B1 --output=size,avail -- "$mountpoint")" || return 1
  read -r total available <<< "${report##*$'\n'}"
  if (( total == 0 ))
  then
    printf '%s: no block capacity reported\n' "$mountpoint"
    return 0
  fi
  printf '%s: %s bytes available of %s (%s%%); minimum %s%%\n' \
    "$mountpoint" "$available" "$total" "$(( available * 100 / total ))" "$minimum"
  (( available * 100 >= total * minimum ))
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
