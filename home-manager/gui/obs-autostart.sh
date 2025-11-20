#!/usr/bin/env bash

obs-studio::command() {
  # NOTE order matters here!
  if command -v obs &>/dev/null
  then
    echo obs
    return 0
  fi

  if flatpak list --user --app | grep -q "com.obsproject.Studio"
  then
    echo flatpak run --user com.obsproject.Studio
    return 0
  fi

  return 1
}

# shellcheck disable=SC2120
obs-studio::start() {
  local start_scene="${1:-Joining soon}"
  local obs_args=(--minimize-to-tray --startvirtualcam --scene "$start_scene")
  local -a obs_cmd=()

  if ! mapfile -t obs_cmd < <(obs-studio::command)
  then
    echo "OBS Studio is not installed" >&2
    return 1
  fi

  local native_obs
  if [[ "${obs_cmd[*]}" == "obs" ]]
  then
    native_obs=1
    if ! pgrep -af "$(command -v obs)" &>/dev/null
    then
      rm -vrf ~/.config/obs-studio/.sentinel
    fi
  fi

  obs_cmd+=("${obs_args[@]}")

  # Use NVIDIA card explicitly for OBS (if available and not targeting flatpak)
  if [[ -n $native_obs ]] && \
     [[ -e /dev/dri/card1 ]]
  then
    obs_cmd=(nvidia-offload "${obs_cmd[@]}")
  fi

  systemd-cat --identifier='obs-studio' -- "${obs_cmd[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  obs-studio::start "${1:-${OBS_SCENE:-Joining soon}}"
fi
