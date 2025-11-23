#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--class CLASS] [--title TITLE] [--cmd CMD] [CLASS]"
}

app_address() {
  local class="$1"
  local title="$2"

  local filter='.class == $class'

  if [[ -n "$title" ]]
  then
    filter="(${filter}) and (.title | test(\$title; \"i\"))"
  fi

  hyprctl -j clients | \
    jq -er --arg class "$class" --arg title "$title" \
      "[.[] | select($filter)][0].address"
}

app_is_running() {
  local addr
  addr="$(app_address "$@")"
  [[ -n "$addr" ]]
}

focus_app() {
  # local class="$1" title="$2"
  # hyprctl dispatch focuswindow "^(${class})\$"
  local addr="$1"
  hyprctl dispatch focuswindow "address:$addr"
}

launch_app() {
  local cmd="$1"
  hyprctl dispatch exec -- "$cmd"
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --class)
        APP_CLASS="$2"
        shift 2
        ;;
      --title)
        APP_TITLE="$2"
        shift 2
        ;;
      --cmd)
        APP_CMD="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  APP_CLASS="${APP_CLASS:-$1}"
  APP_CMD="${APP_CMD:-$APP_CLASS}"

  if [[ -z "$APP_CLASS" ]]
  then
    usage >&2
    exit 2
  fi

  echo "$0 - class: \"$APP_CLASS\" - title: \"$APP_TITLE\" - cmd: \"$APP_CMD\"" >&2

  APP_ADDRESS="$(app_address "$APP_CLASS" "$APP_TITLE")"

  echo "app addr: \"$APP_ADDRESS\"" >&2

  if [[ -n "$APP_ADDRESS" && "$APP_ADDRESS" != "null" ]]
  then
    focus_app "$APP_ADDRESS"
  else
    launch_app "${APP_CMD}"
  fi
fi
