#!/usr/bin/env bash

# Monit sleeps until the next cycle on the wall clock, so a backwards clock step
# (rofl-12 jumped +33d and back on 2026-10-08) leaves it asleep, and silent in
# Monarch, for as long as the clock had been ahead. Watch for such steps by
# comparing CLOCK_REALTIME against the monotonic time between runs, and reload
# monit when they diverge.

STATE_FILE="${MONIT_CLOCK_WATCH_STATE:-/run/monit-clock-watch/offset}"
THRESHOLD="${MONIT_CLOCK_WATCH_THRESHOLD:-30}"

clock_offset() {
  local real mono

  real="$(date +%s.%N)"
  mono="$(awk '{ print $1 }' /proc/uptime)"
  awk -v real="$real" -v mono="$mono" 'BEGIN { printf "%.0f\n", real - mono }'
}

main() {
  local offset previous delta

  offset="$(clock_offset)"

  if [[ -r "$STATE_FILE" ]]
  then
    previous="$(<"$STATE_FILE")"
    delta=$((offset - previous))

    if ((delta > THRESHOLD || delta < -THRESHOLD))
    then
      printf 'System clock stepped by %ss, reloading monit\n' "$delta" >&2
      systemctl reload monit.service
    fi
  fi

  printf '%s\n' "$offset" >"$STATE_FILE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
