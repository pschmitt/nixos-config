#!/usr/bin/env bash

# shellcheck disable=SC2120
obs-studio::start() {
  local start_scene="${1:-🚬 brb}"
  local obs_bin

  if ! obs_bin=$(command -v obs 2>/dev/null) || [[ -z $obs_bin ]]
  then
    echo "OBS Studio is not installed" >&2
    return 1
  fi

  if ! pgrep -af "$(command -v obs)" &>/dev/null
  then
    rm -vrf ~/.config/obs-studio/.sentinel
  fi

  local -a obs_cmd=(
    "$obs_bin"
    --minimize-to-tray
    --startvirtualcam
    --scene "$start_scene"
  )

  # Use NVIDIA card explicitly for OBS (if available and not targeting flatpak)
  if [[ -e /dev/dri/card1 ]]
  then
    obs_cmd=(nvidia-offload "${obs_cmd[@]}")
  fi

  systemd-cat --identifier='obs-studio' -- "${obs_cmd[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  obs-studio::start "${1:-${OBS_SCENE:-🚬 brb}}"
fi
