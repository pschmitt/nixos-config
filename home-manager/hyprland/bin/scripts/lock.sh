#!/usr/bin/env bash

has() {
  command -v "$1" >/dev/null 2>&1
}

pause_media_playback() {
  playerctl pause
}

kill-lock-cmd() {
  killall gtklock
  killall -USR1 swaylock
  killall -USR1 hyprlock
}

lock-cmd() {
  if has hyprlock
  then
    hyprlock-cmd
    return 0
  fi

  if has swaylock
  then
    swaylock-cmd
    return 0
  fi

  return 1
}

gtklock-cmd() {
  # gtklock-with-modules is custom package (NixOS)
  if has gtklock-with-modules
  then
    echo gtklock-with-modules
    return 0
  elif has gtklock
  then
    echo gtklock
    return 0
  fi

  return 1
}

swaylock-cmd() {
  local cmd=(swaylock)

  # Check if the swaylock implementation is swaylock-effects
  if swaylock --help 2>&1 | grep -q -- --screenshots
  then
    cmd=(
      swaylock
        --screenshots
        --clock
        --indicator
        --show-failed-attempts
        --indicator-radius 100
        --indicator-thickness 7
        --effect-blur 9x8
        --effect-pixelate 20
        --effect-vignette 0.5:0.5
        --ring-color bb00cc
        --key-hl-color 880033
        --line-color 00000000
        --inside-color 00000088
        --separator-color 00000000
    )
  fi

  echo "${cmd[@]}"
}

hyprlock-cmd() {
  local cmd=(hyprlock --grace 2)
  echo "${cmd[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  JOURNAL_IDENTIFIER="${JOURNAL_IDENTIFIER:-hyprland-lock}"

  case "$1" in
    --now)
      shift
      ;;
    *)
      if has chayang
      then
        chayang -d "${CHAYANG_DELAY:-5}" || exit
      fi
      ;;
  esac

  LOCK_CMD=$(lock-cmd)

  if [[ -z "$LOCK_CMD" ]]
  then
    notify-send -u critical "NO LOCK COMMAND FOUND." "Please install hyprlock or swaylock"
    exit 1
  fi

  # Avoid running multiple instances of gtklock/swaylock
  kill-lock-cmd

  eval systemd-cat --identifier="$JOURNAL_IDENTIFIER" -- "$LOCK_CMD"
fi
