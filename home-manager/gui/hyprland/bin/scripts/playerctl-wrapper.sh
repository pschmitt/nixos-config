#!/usr/bin/env bash

usage() {
  printf 'Usage: %s play|pause|toggle|next|previous|status\n' "$(basename "$0")"
}

playerctl_all() {
  playerctl --all-players "$@"
}

playerctl_but_kdeconnect() {
  local -a players
  local kdeconnect_player

  mapfile -t players < <(playerctl --list-all)
  kdeconnect_player="$(printf '%s\n' "${players[@]}" | grep -m 1 kdeconnect || true)"

  if [[ -n "$kdeconnect_player" ]] && printf '%s\n' "${players[@]}" | grep -qv "$kdeconnect_player"
  then
    playerctl --ignore-player "$kdeconnect_player" "$@"
    return
  fi

  playerctl "$@"
}

playing() {
  playerctl_all status | grep -qi playing
}

pause() {
  playerctl_all pause
}

play() {
  playerctl_but_kdeconnect play
}

play_pause() {
  if playing
  then
    pause
  else
    play
  fi
}

next() {
  playerctl_but_kdeconnect next
}

previous() {
  playerctl_but_kdeconnect previous
}

main() {
  if [[ "$#" -eq 0 ]]
  then
    usage >&2
    return 2
  fi

  if [[ -n "${DEBUG:-}" ]]
  then
    notify-send "playerctl-wrapper.sh $*"
  fi

  case "$1" in
    help|h|-h|--help)
      usage
      ;;
    play|p|resume)
      play
      ;;
    pause|ps|P)
      pause
      ;;
    play-pause|toggle|pp|t)
      play_pause
      ;;
    next|nxt|n)
      next
      ;;
    previous|prev|pre)
      previous
      ;;
    status|s)
      if playing
      then
        printf 'playing\n'
      else
        printf 'nyet\n'
        return 1
      fi
      ;;
    *)
      printf 'Unknown command: %s\n' "$1" >&2
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
