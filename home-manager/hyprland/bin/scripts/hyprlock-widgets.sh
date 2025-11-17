#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") widget"
}


battery::icon() {
  local percent="$1"
  local state="$2"

  # Keep icon set in sync with the Waybar module to have a consistent battery
  # look everywhere (see home-manager/hyprland/waybar/config.nix).
  local -a discharging_icons=(
    "󰁺" # 0-19%
    "󰁼" # 20-39%
    "󰁾" # 40-59%
    "󰂁" # 60-79%
    "󰁹" # 80-100%
  )

  case "$state" in
    charging|pending-charge)
      echo "󰂅"
      return
      ;;
    fully-charged)
      echo "󰂋"
      return
      ;;
  esac

  if [[ "$percent" -ge 98 ]]
  then
    echo "󰂋"
    return
  fi

  local bucket=$(( percent / 20 ))
  if (( bucket >= ${#discharging_icons[@]} ))
  then
    bucket=$((${#discharging_icons[@]} - 1))
  fi
  echo "${discharging_icons[$bucket]}"
}

battery::json() {
  # NOTE jc's acpi parser chokes on:
  # » acpi -b
  # Battery 0: Charging, 79%, charging at zero rate - will never fully charge.
  #
  # acpi -b | jc --acpi | jq '.[]'

  upower --battery | jc --upower | jq '.[]'
}

battery::widget() {
  local data
  data=$(battery::json)

  local percent state
  IFS=$'\t' read -r percent state < <(jq -r  <<< "$data" '
    .detail | [(.percentage | floor), (.state | ascii_downcase)] | @tsv
  ')

  if [[ -z "$percent" || "$percent" == "null" ]]
  then
    echo "󰂃 --"
    return
  fi

  local emoji
  emoji=$(battery::icon "$percent" "$state")

  local prefix=""
  if [[ "$state" == "discharging" && "$percent" -lt 15 ]]
  then
    prefix="!! "
  fi

  echo "${prefix}${emoji} ${percent}%"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  case "$1" in
    bat*)
      battery::widget
      ;;
    *)
      echo "Unknown command: $1"
      exit 2
      ;;
  esac
fi
