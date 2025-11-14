#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if command -v hypridle 2>/dev/null
  then
    exec hypridle
    exit "$?"
  fi

  lock="$(pwd)/lock.sh"

  # swayidle -w \
  #   timeout 300 "$lock" \
  #   timeout 600 'hyprctl dispatch dpms off' \
  #   before-sleep "$lock --now" \
  #   after-resume 'hyprctl dispatch dpms on'

  swayidle -w \
    timeout 300 "$lock" \
    before-sleep "$lock --now"
fi
