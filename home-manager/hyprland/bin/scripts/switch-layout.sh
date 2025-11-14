#!/usr/bin/env bash

get_current_layout() {
  hyprctl -j getoption general:layout | jq -er '.str'
}

switch_to_layout() {
  local layout="$1"

  echo "Switching to $layout"

  hyprctl keyword general:layout "$layout"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  CURRENT_LAYOUT="$(get_current_layout)"

  echo "Current layout is $CURRENT_LAYOUT"

  case "$CURRENT_LAYOUT" in
    master)
      TARGET_LAYOUT="dwindle"
      ;;
    dwindle)
      TARGET_LAYOUT="master"
      ;;
    *i3|hy3)
      # NOTE: requires https://github.com/outfoxxed/hy3
      TARGET_LAYOUT="hy3"
      ;;
    *)
      echo "Unknown layout: $CURRENT_LAYOUT" >&2
      exit 1
      ;;
  esac

  switch_to_layout "$TARGET_LAYOUT"
fi

