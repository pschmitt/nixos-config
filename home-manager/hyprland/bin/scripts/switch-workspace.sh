#!/usr/bin/env bash

# This script is used to switch to the previous workspace
# It requires hyprevents
# https://github.com/hyprwm/Hyprland/issues/4332

usage() {
  echo "Usage: $0 [previous]"
}

current_ws() {
  hyprctl activeworkspace -j | jq -er .id
}

switch_to_previous_ws() {
  local previous_ws
  previous_ws=$(cat "$WS_PREV_FILE" 2>/dev/null)

  if [[ -z "$previous_ws" ]]
  then
    echo "No previous workspace found, defaulting to hyprctl dispatch workspace previous" >&2
    previous_ws="previous"
  fi

  hyprctl dispatch workspace "$previous_ws"
}

switch_to_ws() {
  local current_ws target_ws="$1"
  current_ws="$(current_ws)"

  if [[ "$current_ws" == "$target_ws" ]]
  then
    switch_to_previous_ws
    return "$?"
  fi

  hyprctl dispatch workspace "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
  source ./hyprevents-handler.sh

  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    prev*)
      switch_to_previous_ws
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]
      then
        switch_to_ws "$1"
        exit "$?"
      fi

      usage >&2
      exit 2
      ;;
  esac
fi
