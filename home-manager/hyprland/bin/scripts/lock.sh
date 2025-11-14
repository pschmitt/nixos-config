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
  # TODO killall hyprlock
  # https://github.com/hyprwm/hyprlock/issues/16
}

lock-cmd() {
  # FIXME gtklock is currently broken on Hyprland:
  # ** (gtklock:628736): CRITICAL **: 15:26:15.805: Your compositor doesn't support wlr-input-inhibitor
  # local gtklock
  # gtklock=$(gtklock-cmd)
  # if [[ -n "$gtklock" ]]
  # then
  #   echo "$gtklock"
  #   return 0
  # fi

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

update-hass-entity() {
  {
    for _ in $(seq 1 10)
    do
      ~/.config/hacompanion/bin/update-entity.sh lockscreen_state
      sleep .5
    done
  } &
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

  if [[ -z "$NO_BULLSHIT" ]]
  then
    update-hass-entity
  fi

  # Avoid running multiple instances of gtklock/swaylock
  kill-lock-cmd

  eval systemd-cat --identifier="$JOURNAL_IDENTIFIER" -- "$LOCK_CMD"

  # CURRENT_WS_CLIENTS=$(zhj hyprctl::current-workspace-clients | jq -s length)
  #
  # # If currently on an empty workspace, try switching to the previous one
  # if [[ "$CURRENT_WS_CLIENTS" -eq 0 ]]
  # then
  #   notify-send -t 5000 -a "$0" "$(basename "$0")" "Switching to previous workspace"
  #   ~/.config/hypr/bin/switch-workspace.sh prev
  # fi
fi
