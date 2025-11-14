#!/usr/bin/env bash

pypr_reset() {
  killall pypr
  hyprctl dispatch exec -- pypr
}

hyprctl() {
  echo "Running 'hyprctl $*'"
  command hyprctl "$@"
}

source_file() {
  local config_file="$1"

  # Monitor config
  hyprctl --batch "$(grep -E '^monitor ?= ?' "$config_file" | \
    sed -r 's/^monitor ?= ?/keyword monitor /' | \
    tr '\n' ';')"

  # Focus on monitor
  local focus
  focus="$(awk -F ' ?= ?' '/^focusmonitor/ { print $2; exit }' "$config_file")"
  if [[ -n "$focus" ]]
  then
    hyprctl dispatch focusmonitor "$focus"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  FILE="$1"
  DEFAULT_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/hypr/config.d/monitors-${HOSTNAME:-$(hostname)}.conf"

  # trap pypr_reset EXIT

  if [[ -z "$FILE" ]]
  then
    if [[ -r "$DEFAULT_FILE" ]]
    then
      echo "Using default file: $DEFAULT_FILE"
      FILE="$DEFAULT_FILE"
    else
      echo "No file specified and default file not found: $DEFAULT_FILE" >&2
      hyprctl keyword monitor ',preferred,auto,1'
      exit "$?"
      # exit 2
    fi
  fi

  source_file "$FILE"
fi
