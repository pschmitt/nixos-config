#!/usr/bin/env bash

SELF="$(basename "$0")"
DEBUG="${DEBUG:-}"
# Password entry timeout
TIMEOUT="${TIMEOUT:-60}"
# milliseconds!
TMUX_DISPLAY_TIMEOUT="${TMUX_DISPLAY_TIMEOUT:-2000}"

usage() {
  echo "Usage: ${SELF} BUFFER"
}

_log() {
  if [[ -n "$DEBUG" ]]
  then
    echo "[${SELF}]: $*" >&2
  fi
}

_tmux_has_popup() {
  # DEBUG: Set FORCE_WINDOW to force a window instead of a popup
  if [[ -n "$FORCE_WINDOW" ]] || [[ -n "$FORCE_WIN" ]]
  then
    return 1
  fi
  # Popups need tmux 3.2, which Nix always provides
  return 0
}

_tmux_get_client_size() {
  tmux display-message -p -F '#{client_width} #{client_height}'
}

_tmux_get_popup_size() {
  local client_height
  local client_width

  read -r client_width client_height < <(_tmux_get_client_size)

  local popup_height="50%"
  local popup_width="50%"

  if [[ "$client_width" -lt 60 ]] || [[ "$client_height" -lt 30 ]]
  then
    popup_width="80%"
    popup_height="80%"
  fi

  echo "-w $popup_width -h $popup_height"
}

_tmux_display_popup() {
  local -a extra_args
  read -ra extra_args < <(_tmux_get_popup_size)

  tmux display-popup "${extra_args[@]}" "$@"
}

_tmux_notify() {
  local msg="$1"
  local timeout="${2:-${TMUX_DISPLAY_TIMEOUT}}"
  local extra_args=()

  if tmux display-message --help 2>&1 | grep -qi '\[-d delay\]'
  then
    extra_args+=(-d "$timeout")
  fi

  tmux display-message "${extra_args[@]}" "$msg"
}

_tmux_wait() {
  local cmd="$1"
  local win="${2:-tmux-tmp}"
  local signal="${3:-tmux_tmp_done}"
  local timeout="${4:-${TIMEOUT}}"
  local popup

  local tmux_client
  tmux_client=$(tmux display-message -p -F '#{client_name}')

  if _tmux_has_popup
  then
    popup=1
  fi

  # Show popup/create window
  cmd="trap 'echo \"TRAP - send signal ${signal}\";
             tmux wait-for -U \"${signal}\";
             tmux wait-for -SU \"${signal}\";' 0
       printf '%s\n' 'Fetching password... [${cmd}]'
       ${cmd}"
  _log "Running $cmd"

  # FIXME Why do we need different locking for popup and window?!
  if [[ -n "$popup" ]]
  then
    # display-popup is blocking
    _tmux_display_popup -E "$cmd" &
  else
    tmux neww -n "$win" "$cmd"
  fi

  # Timeout process
  (
    _log "Starting timeout counter ($timeout seconds)"
    sleep "$timeout"
    _log 'Timed out!'

    if [[ -n "$popup" ]]
    then
      # kill popup, should trigger the signal
      tmux display-popup -c "$tmux_client" -CE
    else
      # Close password window
      win_id="$(tmux list-windows -F "#{window_name} #{window_id}" | \
        awk "/^${win} / {print \$2; exit}")"

      if [[ -n "$win_id" ]]
      then
        _log "Killing window: $win_id"
        tmux kill-window -t "$win_id"
      else
        _log "ERROR: Could not find any window named $win"
      fi
    fi

    _tmux_notify '⏰ Password entry timed out.'

    _log "Sending TMUX signal $signal"
    tmux wait-for -U "${signal}"
    tmux wait-for -SU "${signal}"
  )&

  # Wait for command to complete
  _log "Make signal $signal locking"
  tmux wait-for -L "$signal"
  _log "Wait for signal $signal"
  tmux wait-for "$signal"
  _log 'Signal received!'

  # Kill background timeout job
  # shellcheck disable=2046
  kill $(jobs -p) >&2
}

set_buffer() {
  if [[ -n "$DEBUG" ]]
  then
    _tmux_wait "bash -xc 'sleep 120'" "tmp_${1}" "tmp_${1}_done"
  else
    _tmux_wait "zhj rbw::get --tmux '$1'" "pswd_${1}" "pswd_${1}_done"
  fi

  local rc="$?"

  if [[ "$rc" -ne 0 ]]
  then
    _tmux_notify '🤦 set_buffer failed!'
    return "$rc"
  fi
}

paste_buffer() {
  local quiet

  case "$1" in
    q|quiet|-q|--quiet)
      shift
      quiet=1
      ;;
  esac

  # NOTE To make the buffer persist you need to remove the "-d" on the next line
  if tmux paste-buffer -b "$1" -d >/dev/null 2>&1
  then
    _tmux_notify '📋 Pasted!' 1000
    return
  fi

  if [[ -z "$quiet" ]]
  then
    _tmux_notify '🤦 Paste buffer failed!'
  fi

  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  if [[ -n "$DEBUG" ]]
  then
    set -ex
  fi

  BUFFER="$1"

  _log "START"

  if [[ "$#" -lt 1 ]]
  then
    usage
    exit 2
  fi

  case "$1" in
    help|h|--help|-h)
      usage
      exit 0
      ;;
  esac

  if ! paste_buffer -q "$BUFFER"
  then
    if set_buffer "$BUFFER"
    then
      paste_buffer -q "$BUFFER"
    fi
  fi
fi
