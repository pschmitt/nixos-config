#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") widget"
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

  # NOTE below is for acpi -b | jc --acpi
  # local percent
  # percent=$(jq -r '.charge_percent' <<< "$data")
  # local state
  # state=$(jq -r '.state' <<< "$data")
  local percent state
  IFS=$'\t' read -r percent state < <(jq -r  <<< "$data" '
    .detail | [(.percentage | floor), (.state | ascii_downcase)] | @tsv
  ')

  local emoji="🔋"
  if [[ "$percent" -lt 20 ]]
  then
    emoji="🪫"
  fi

  if [[ "$state" == "charging" ]]
  then
    emoji="🔌"
  fi

  echo "${emoji}${percent}%"
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
