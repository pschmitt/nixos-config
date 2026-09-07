#!/usr/bin/env bash

has() {
  command -v "$1" &>/dev/null
}

is_noctalia_running() {
  has noctalia && { pgrep -x noctalia || pgrep -x .noctalia-wrapp; } &>/dev/null
}

is_locked() {
  if is_noctalia_running
  then
    [[ "$(noctalia msg status 2>/dev/null | jq -re '.locked // false')" == "true" ]] && return 0
  fi
  pgrep -x hyprlock &>/dev/null
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  JOURNAL_IDENTIFIER="${JOURNAL_IDENTIFIER:-lockscreen}"

  if [[ -z $FORCE ]] && is_locked
  then
    # Avoid re-triggering when locker is already active
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

  if is_noctalia_running
  then
    exec noctalia msg session lock
  fi

  eval systemd-cat --identifier="$JOURNAL_IDENTIFIER" -- "hyprlock"
fi
