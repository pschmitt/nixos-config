#!/usr/bin/env bash

DEFAULT_BLINK_INTERVAL=.25

usage() {
  echo "Usage: $(basename "$0") [-d DISPLAY_TIME] [-s STYLE] MESSAGE"
}

echo_debug() {
  if [[ -n "$DEBUG" ]]
  then
    echo "$*" >&2
  fi
}

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local raw_value

  raw_value=$(tmux show-option -gqv "$option")

  echo "${raw_value:-$default_value}"
}

get_display_time() {
  local convert_to_seconds
  local val

  case "$1" in
    -s|--seconds)
      convert_to_seconds=1
      ;;
  esac

  val="$(get_tmux_option display-time 1000)"

  if [[ -n "$convert_to_seconds" ]]
  then
    bc -l <<< "scale=2; $val / 1000"
  else
    echo "$val"
  fi
}

set_display_time() {
  echo_debug "Setting display-time to $1"
  tmux set-option -g display-time "$1"
}

get_message_style() {
  get_tmux_option message-style
}

set_message_style() {
  echo_debug "Setting message-style to $1"
  tmux set-option -g message-style "$1"
}

reset_values() {
  if [[ -n "$RESET_DISPLAY_TIME" ]]
  then
    # Convert display time back to ms
    # NOTE The /1 part is so that bc respects the scale param
    local og_display_time_ms
    og_display_time_ms="$(bc -l <<< "scale=0; $OG_DISPLAY_TIME * 1000 / 1")"
    echo_debug "Resetting display time to $og_display_time_ms"
    set_display_time "$og_display_time_ms"
  fi

  if [[ -n "$RESET_MESSAGE_STYLE" ]]
  then
    echo_debug "Resetting message style to $OG_MESSAGE_STYLE"
    set_message_style "$OG_MESSAGE_STYLE"
  fi
}

invert_message_style() {
  local bg
  local extra_attrs
  local fg
  local new_style
  local style

  style="${1:-$(get_message_style)}"

  if [[ "$style" == "default" ]] || [[ -z "$style" ]]
  then
    style="fg=white,bg=black,bold"
  fi

  read -r fg bg extra_attrs <<< \
    "$(sed -rn 's/fg=([^,]+),bg=([^,]+)(,.+)/\1 \2 \3/p' <<< "$style")"

  new_style="fg=${bg},bg=${fg}${extra_attrs}"
  echo_debug "Invert style: $style -> $new_style"
  echo "$new_style"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ -n "$*" ]]
  do
    case "$1" in
      --help|-h|help|h)
        usage
        exit 0
        ;;
      --debug|-D)
        DEBUG=1
        shift
        ;;
      -b|--blink)
        if [[ "$2" =~ ^[0-9]+ ]]
        then
          # Blink interval provided
          BLINK="$2"
          shift 2
        else
          BLINK="true"
          shift
        fi
        ;;
      -d|--delay)
        if ! [[ "$2" =~ ^[0-9]+ ]] || [[ "$2" == 0* ]]
        then
          echo "Invalid display time: $2" >&2
          exit 2
        fi
        # Convert to milliseconds
        DISPLAY_TIME="$2"
        DISPLAY_TIME="$(( DISPLAY_TIME * 1000 ))"
        shift 2
        ;;
      -s|--style)
        MESSAGE_STYLE="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  # Grab original values
  OG_DISPLAY_TIME="$(get_display_time --seconds)"
  OG_MESSAGE_STYLE="$(get_message_style)"

  # Reset values at exit
  trap 'reset_values' EXIT INT

  # Set display-time
  if [[ -n "$DISPLAY_TIME" ]] && [[ "$OG_DISPLAY_TIME" != "$DISPLAY_TIME" ]]
  then
    RESET_DISPLAY_TIME=1
    set_display_time "$DISPLAY_TIME"
  fi

  # Set message style
  if [[ -n "$MESSAGE_STYLE" ]]
  then
    if [[ "$OG_MESSAGE_STYLE" != "$MESSAGE_STYLE" ]]
    then
      RESET_MESSAGE_STYLE=1
      set_message_style "$MESSAGE_STYLE"
    fi
  fi

  # Display message
  tmux display-message "$@"

  # Blink
  if [[ -n "$BLINK" ]]
  then
    if [[ "$BLINK" == true ]]
    then
      BLINK_INTERVAL="$DEFAULT_BLINK_INTERVAL"
    else
      BLINK_INTERVAL="$BLINK"
    fi

    DISPLAY_TIME="${DISPLAY_TIME:-${OG_DISPLAY_TIME}}"
    MESSAGE_STYLE="${MESSAGE_STYLE:-${OG_MESSAGE_STYLE}}"

    echo_debug "OG_DISPLAY_TIME=$OG_DISPLAY_TIME DISPLAY_TIME=$DISPLAY_TIME BLINK_INTERVAL=$BLINK_INTERVAL"

    for _ in $(seq "$(bc <<< "($DISPLAY_TIME * (1 / $BLINK_INTERVAL) / 1000)")")
    do
      MESSAGE_STYLE="$(invert_message_style "$MESSAGE_STYLE")"
      set_message_style "$MESSAGE_STYLE"
      sleep "$BLINK_INTERVAL"
    done
  elif [[ -n "$DISPLAY_TIME" ]]
  then
    # We need to sleep here since otherwise the message-style may get reset
    # too early and the message will be displayed with the colors originally
    # defined in tmux.conf
    sleep "$DISPLAY_TIME"
  fi
fi
