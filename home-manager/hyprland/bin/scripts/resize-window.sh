#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [-c|--center] [-f|--float] [-w|--width <width>] [-H|--height <height>]"
}

hyprctl() {
  echo -e "\e[95m🚀 Running 'hyprctl $*'\e[0m" >&2
  command hyprctl "$@"
}

monitor_specs() {
  local monitor_id="$1"
  hyprctl monitors -j | \
    jq -er --argjson mon_id "$monitor_id" '
      .[] | select(.id == $mon_id) as $mon |
      (if ($mon.transform % 2 == 0) then
        { w: $mon.width, h: $mon.height }
      else
        { w: $mon.height, h: $mon.width }
      end) as $rotated |
      ( ($rotated.w / $mon.scale) ) as $logicalWidth |
      ( ($rotated.h / $mon.scale) ) as $logicalHeight |
      "\(($mon.reserved[0] + $mon.reserved[3])) \(($mon.reserved[1] + $mon.reserved[2])) \($mon.x) \($mon.y) \($logicalWidth) \($logicalHeight)"'
}

get_window_data() {
  local window="$1"

  if [[ -z "$window" ]]
  then
    hyprctl activewindow -j
    return "$?"
  fi

  # NOTE This will only return the first match!
  hyprctl -j clients | jq -er --arg class "$window" \
    '[.[] | select(.class  == $class)][0]'
}

get_window_addr() {
  jq -er '.address // ""'
}

get_window_monitor_id() {
  jq -er '.monitor // ""'
}

is_floating() {
  jq -er .floating > /dev/null
}

focussed_window_addr() {
  hyprctl -j activewindow | jq -er .address
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ -n "$*" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -f|--float)
        FLOAT=1
        shift
        ;;
      -c|--center)
        CENTER=1
        shift
        ;;
      -p|--position)
        POSITION="$2"
        shift 2
        ;;
      -w|--width)
        # NOTE we remove any trailing '%' here
        WIDTH="${2%%%}"
        shift 2
        ;;
      -H|--height)
        HEIGHT="${2%%%}"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "$WIDTH" || -z "$HEIGHT" ]]
  then
    usage
    exit 2
  fi

  TARGET_WINDOW="$1"
  WINDOW_DATA="$(get_window_data "$TARGET_WINDOW")"
  WINDOW_ADDR="$(get_window_addr <<< "$WINDOW_DATA")"
  WINDOW_MONITOR_ID="$(get_window_monitor_id <<< "$WINDOW_DATA")"

  if [[ -z "$WINDOW_ADDR" ]]
  then
    echo "No window found with class '$TARGET_WINDOW'"
    exit 1
  fi

  if [[ -n "$FLOAT" || -n "$CENTER" ]] && ! is_floating <<< "$WINDOW_DATA"
  then
    hyprctl dispatch togglefloating "address:$WINDOW_ADDR"
  fi

  read -r \
    RESERVED_X RESERVED_Y \
    MONITOR_X MONITOR_Y \
    MONITOR_WIDTH MONITOR_HEIGHT \
    <<< "$(monitor_specs "$WINDOW_MONITOR_ID")"

  # width and height are percentages
  WINDOW_WIDTH="$(awk -v mw="$MONITOR_WIDTH" -v pct="$WIDTH" 'BEGIN { printf("%.0f", mw * pct / 100) }')"
  WINDOW_HEIGHT="$(awk -v mh="$MONITOR_HEIGHT" -v pct="$HEIGHT" 'BEGIN { printf("%.0f", mh * pct / 100) }')"
  # NOTE Do not put a space after the comma!
  hyprctl dispatch "resizewindowpixel exact $WINDOW_WIDTH $WINDOW_HEIGHT,address:$WINDOW_ADDR"

  if [[ -n "$CENTER" ]]
  then
    POSITION=center
  fi

  case "$POSITION" in
    center)
      WINDOW_POS_X="$(awk -v mx="$MONITOR_X" -v rx="$RESERVED_X" -v mw="$MONITOR_WIDTH" -v ww="$WINDOW_WIDTH" 'BEGIN { printf("%.0f", mx + rx + ((mw - ww) / 2)) }')"
      WINDOW_POS_Y="$(awk -v my="$MONITOR_Y" -v ry="$RESERVED_Y" -v mh="$MONITOR_HEIGHT" -v wh="$WINDOW_HEIGHT" 'BEGIN { printf("%.0f", my + ry + ((mh - wh) / 2)) }')"
      ;;
    center-top|ctop|ct)
      WINDOW_POS_X="$(awk -v mx="$MONITOR_X" -v rx="$RESERVED_X" -v mw="$MONITOR_WIDTH" -v ww="$WINDOW_WIDTH" 'BEGIN { printf("%.0f", mx + rx + ((mw - ww) / 2)) }')"
      WINDOW_POS_Y="$(awk -v my="$MONITOR_Y" -v ry="$RESERVED_Y" 'BEGIN { printf("%.0f", my + ry) }')"
      ;;
    center-bottom|cbottom|cb)
      WINDOW_POS_X="$(awk -v mx="$MONITOR_X" -v rx="$RESERVED_X" -v mw="$MONITOR_WIDTH" -v ww="$WINDOW_WIDTH" 'BEGIN { printf("%.0f", mx + rx + ((mw - ww) / 2)) }')"
      # FIXME This here is only correct if the bar is on top!
      # If is is on the bottom, we need to subtract the bar height from
      # the Y position, ie RESERVED_Y
      WINDOW_POS_Y="$(awk -v mh="$MONITOR_HEIGHT" -v wh="$WINDOW_HEIGHT" 'BEGIN { printf("%.0f", mh - wh) }')"
      ;;
  esac

  if [[ -n "$WINDOW_POS_X" && -n "$WINDOW_POS_Y" ]]
  then
    hyprctl dispatch "movewindowpixel exact ${WINDOW_POS_X} ${WINDOW_POS_Y},address:${WINDOW_ADDR}"
  fi
fi
