#!/usr/bin/env bash

is_screencasting() {
  jq -e '.state == "on"' "${TMPDIR:-/tmp}/screencast.json" &>/dev/null
}

screencasting_apps() {
  jq -er '.apps | join(", ")' "${TMPDIR:-/tmp}/screencast.json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  ICON_ON=''
  # ICON_OFF=''
  APP=screencast
  CLASS="custom-screencast"
  TEXT=""

  # Check if we are being invoked by waybar
  case "$1" in
    format)
      if is_screencasting
      then
        ICON="$ICON_ON"
        TEXT='<span foreground="#e27978" font-weight="bold">SCREENCASTING</span>'
        TOOLTIP="Screencasting with $(screencasting_apps)"
        ALT="on"
      else
        ICON=""
        TEXT=""
        ALT="off"
        TOOLTIP="Not screencasting"
      fi

      jq -ernc --arg app "$APP" --arg icon "$ICON" \
        --arg class "$CLASS" --arg alt "$ALT" \
        --arg text "$TEXT" --arg tooltip "$TOOLTIP" \
        '{
          "text": (if $text != "" then ($icon + " " + $text) else $icon end),
          "alt": $alt,
          "class": $class,
          "tooltip": $tooltip
        }'
      exit 0
      ;;
  esac
fi
