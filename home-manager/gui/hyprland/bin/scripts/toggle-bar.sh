#!/usr/bin/env bash

set -euo pipefail

# Ordered wishlist of bar services to cycle through. Hosts that don't enable
# a given service (eg. dms while its module is skipped) just skip it.
CANDIDATE_BARS=(waybar quickshell-bar dms noctalia)

available_bars() {
  local bar

  for bar in "${CANDIDATE_BARS[@]}"
  do
    if systemctl --user cat "${bar}.service" &>/dev/null
    then
      echo "$bar"
    fi
  done

  return 0
}

current_bar() {
  local bar

  for bar in "${BARS[@]}"
  do
    if systemctl --user is-active --quiet "${bar}.service"
    then
      echo "$bar"
      return 0
    fi
  done

  return 1
}

next_bar() {
  local current="$1"
  local i

  for i in "${!BARS[@]}"
  do
    if [[ "${BARS[$i]}" == "$current" ]]
    then
      echo "${BARS[$(( (i + 1) % ${#BARS[@]} ))]}"
      return 0
    fi
  done

  echo "${BARS[0]}"
}

main() {
  local current target bar

  mapfile -t BARS < <(available_bars)

  if [[ "${#BARS[@]}" -eq 0 ]]
  then
    echo "No known bar services found (tried: ${CANDIDATE_BARS[*]})" >&2
    return 1
  fi

  current="$(current_bar)" || true
  target="$(next_bar "${current:-}")"

  for bar in "${BARS[@]}"
  do
    systemctl --user stop "${bar}.service"
  done

  systemctl --user start "${target}.service"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
