#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") widget"
}


battery::json() {
  acpi -b | jc --acpi | jq '.[]'
}

battery::widget() {
  local data
  data=$(battery::json)

  local percent
  percent=$(jq -r '.charge_percent' <<< "$data")
  local state
  state=$(jq -r '.state' <<< "$data")

  local emoji="🔋"
  if [[ "$percent" -lt 20 ]]
  then
    emoji="🪫"
  fi

  if [[ "$state" == "Charging" ]]
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
