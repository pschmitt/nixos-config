#!/usr/bin/env bash

real_hyprctl="${HYPRCTL_REAL:-/run/current-system/sw/bin/hyprctl}"

run_real() {
  exec "$real_hyprctl" "$@"
}

run_real_quiet() {
  "$real_hyprctl" "$@" >/dev/null
}

lua_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"

  printf '%s' "$value"
}

rewrite_iio_batch() {
  local quiet=
  local batch=
  local monitor=
  local monitor_transform=
  local touch_transform=
  local tablet_transform=

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -q)
        quiet=1
        shift
        ;;
      --batch)
        batch="${2:-}"
        shift 2
        ;;
      *)
        return 1
        ;;
    esac
  done

  if [[ -z "${batch:-}" ]]
  then
    return 1
  fi

  if [[ ! "$batch" =~ ^keyword\ monitor\ ([^,]+),transform,([0-9-]+)\ \;\ keyword\ input:touchdevice:transform\ ([0-9-]+)\ \;\ keyword\ input:tablet:transform\ ([0-9-]+)(\ \;\ keyword\ workspace\ m\[([^]]+)\],\ layoutopt:orientation:([a-z]+))?$ ]]
  then
    return 1
  fi

  monitor="$(lua_quote "${BASH_REMATCH[1]}")"
  monitor_transform="${BASH_REMATCH[2]}"
  touch_transform="${BASH_REMATCH[3]}"
  tablet_transform="${BASH_REMATCH[4]}"

  if [[ -n "${quiet:-}" ]]
  then
    run_real_quiet eval "hl.monitor({ output = \"${monitor}\", transform = ${monitor_transform} })"
    run_real_quiet eval "hl.config({ input = { touchdevice = { transform = ${touch_transform} }, tablet = { transform = ${tablet_transform} } } })"
  else
    "$real_hyprctl" eval "hl.monitor({ output = \"${monitor}\", transform = ${monitor_transform} })"
    "$real_hyprctl" eval "hl.config({ input = { touchdevice = { transform = ${touch_transform} }, tablet = { transform = ${tablet_transform} } } })"
  fi
}

main() {
  if rewrite_iio_batch "$@"
  then
    return 0
  fi

  run_real "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
