#!/usr/bin/env bash

zhj() {
  "${HOME}/bin/zhj" "$@"
}

timewarrior_is_on() {
  zhj timewarrior::is-on
}

timewarrior_current_time() {
  zhj timewarrior::today-total --minutes
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  ICON_ON='󱤣'
  APP=timewarrior
  CLASS="custom-timewarrior"
  TEXT=""

  # Check if we are being invoked by waybar
  case "$1" in
    format)
      if timewarrior_is_on
      then
        TIMEW="$(timewarrior_current_time)"
        TEXT="${TIMEW}"
        FIRST_DIGIT="$(sed -nr 's/^(0?([0-9]+):).*/\2/p' <<< "$TIMEW")"

        # Make the text bold if working for more than 7 hours
        if [[ "$FIRST_DIGIT" -gt 7 ]]
        then
          TEXT='<span foreground="#e27978" font-weight="bold">'"${TEXT}"'</span>'
        fi

        ICON="$ICON_ON"
        TOOLTIP="Timewarrior is on"
        ALT="on"
      else
        ICON=""
        TEXT=""
        ALT="off"
        TOOLTIP="Timewarrior is off"
      fi

      jq -ernc \
        --arg app "$APP" --arg icon "$ICON" \
        --arg class "$CLASS" --arg alt "$ALT" \
        --arg text "$TEXT" --arg tooltip "$TOOLTIP" \
        '{
          "text": (if $text != "" then ($icon + " " + $text) else "" end),
          "alt": $alt,
          "class": $class,
          "tooltip": $tooltip
        }'
      exit 0
      ;;
  esac
fi
