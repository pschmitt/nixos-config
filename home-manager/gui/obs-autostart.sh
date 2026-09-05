#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SCENE]

Start OBS Studio with our custom flags.

Options:
  -h, --help        Show this help
      --workdays-only
                    Do nothing unless today is a workday (see below)
      --trace       Enable shell tracing

Workday detection asks Home Assistant for binary_sensor.workday_sensor
(Mon-Fri, minus public holidays). If Home Assistant cannot be reached we fall
back to a plain Mon-Fri check.
EOF
}

obs-studio::ha-secret() {
  local name="$1"
  local file

  for file in \
    "$HOME/.config/sops-nix/secrets/home-assistant/$name" \
    "/run/secrets/home-assistant/$name"
  do
    if [[ -r "$file" ]]
    then
      cat "$file"
      return 0
    fi
  done

  return 1
}

# Mon-Fri, ignoring public holidays. Only used when Home Assistant is
# unreachable (eg. at boot, before the network is up).
obs-studio::is-weekday() {
  local dow
  dow=$(date +%u)

  [[ $dow -le 5 ]]
}

obs-studio::is-workday() {
  local server token state

  if ! server=$(obs-studio::ha-secret server) ||
    ! token=$(obs-studio::ha-secret token)
  then
    echo "Home Assistant credentials unavailable, assuming Mon-Fri" >&2
    obs-studio::is-weekday
    return "$?"
  fi

  state=$(curl -fsSL --max-time 10 \
    -H "Authorization: Bearer $token" \
    "${server%/}/api/states/binary_sensor.workday_sensor" |
    jq -er '.state')

  case "$state" in
    on)
      return 0
      ;;
    off)
      return 1
      ;;
    *)
      echo "Could not query workday sensor, assuming Mon-Fri" >&2
      obs-studio::is-weekday
      return "$?"
      ;;
  esac
}

obs-studio::start() {
  local start_scene="${1:-🚬 brb}"
  local obs_bin

  if ! obs_bin=$(command -v obs 2>/dev/null) || [[ -z $obs_bin ]]
  then
    echo "OBS Studio is not installed" >&2
    return 1
  fi

  if ! pgrep -af "$obs_bin" &>/dev/null
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

main() {
  local workdays_only

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --workdays-only)
        workdays_only=1
        shift
        ;;
      --trace)
        set -x
        shift
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -n "$workdays_only" ]] && ! obs-studio::is-workday
  then
    echo "Not a workday, not starting OBS Studio" >&2
    return 0
  fi

  obs-studio::start "${1:-${OBS_SCENE:-🚬 brb}}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
