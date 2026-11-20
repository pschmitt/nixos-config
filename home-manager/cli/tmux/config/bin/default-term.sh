#!/usr/bin/env bash

# DEBUG
# set -x
# outfile=${1:-/tmp/tmux-term.log}
# exec >"$outfile" 2>&1

tmux_set_default_term() {
  tmux set-option -g default-terminal "$1"
  tmux set-environment -g TERM "$1"

  if [[ -n "$DEBUG" ]]
  then
    notify-send -a "$0" "tmux: Set default terminal to $1"
  fi
}

is_nixos() {
  command -v nixos-help &>/dev/null
}

has_terminfo() {
  local term="$1"

  [[ -z "$term" ]] && return 1

  # Try infocmp first (infocmp is part of ncurses)
  if command -v infocmp &>/dev/null
  then
    infocmp "$term" &>/dev/null && return 0 || return 1
  fi

  # FIXME Below does not take TERMINFO and TERMINFO_DIRS into account
  local first_letter="${term:0:1}"

  # On NixOS the terminfo files reside in /run/current-system/sw/share/terminfo
  if is_nixos
  then
    local PREFIX=/run/current-system/sw
  fi

  [[ -r ${PREFIX:-/usr}/share/terminfo/${first_letter}/${term} ]]
}

fallback_term() {
  local term
  for term in tmux-256color screen-256color xterm-256color
  do
    if has_terminfo "$term"
    then
      echo $term
      return
    fi
  done

  # last resort
  echo "xterm"
}

try_term() {
  local term="$1"

  if [[ "$term" != dumb ]] && has_terminfo "$term"
  then
    echo "$term"
    return 0
  fi

  fallback_term
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  case "$TERMINAL" in
    kitty)
      TERM="xterm-kitty"
      ;;
  esac

  case "$TERM" in
    foot*)
      term=foot
      ;;
    *ghostty*)
      term=xterm-ghostty
      ;;
    *kitty*)
      term=xterm-kitty
      ;;
    xterm*|rxvt*)
      term=xterm-256color
      ;;
    screen*|tmux*)
      # The server may have been started from inside another tmux/screen.
      # tmux emits reverse video instead of italics (sitm -> smso) whenever
      # default-terminal is screen or screen-*, so never inherit that.
      term=tmux-256color
      ;;
    *)
      term="$TERM"
      ;;
  esac

  # DEBUG
  # echo "OG TERM=$TERM (-> $term)" > /tmp/tmux-term.log

  term=$(try_term "$term")

  # DEBUG
  # echo "Set default term to $term" >> /tmp/tmux-term.log
  tmux_set_default_term "$term"
fi
