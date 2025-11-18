#!/usr/bin/env bash

has() {
  command -v "$1" &>/dev/null
}

is_locked() {
  pgrep -x hyprlock &>/dev/null
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  JOURNAL_IDENTIFIER="${JOURNAL_IDENTIFIER:-hyprlock}"

  if [[ -z $FORCE ]] && is_locked
  then
    # Avoid sending SIGUSR1 to the locker when it's already active (hypridle re-triggers lock.sh).
    exit 0
  fi

  case "$1" in
    -d|--delay)
      DELAY="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=1
      shift
      ;;
    -n|--now)
      NOW=1
      shift
      ;;
  esac

  if [[ -z $NOW ]] && has chayang
  then
    chayang -d "${DELAY:-5}" || exit
  fi

  eval systemd-cat --identifier="$JOURNAL_IDENTIFIER" -- "hyprlock"
fi
