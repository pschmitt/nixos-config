#!/usr/bin/env bash

set -euo pipefail

toggle_mic_mute() {
  if command -v obs-control >/dev/null 2>&1 && obs-control toggle-mute
  then
    return 0
  fi

  if ! pactl set-source-mute rnnoise_source toggle
  then
    noctalia msg mic-mute
    return $?
  fi

  local mute_state
  mute_state="$(pactl get-source-mute rnnoise_source)"
  if [[ "$mute_state" == *yes* ]]
  then
    osd native mic-volume muted || notify-send '🔇 Microphone muted'
  else
    osd native mic-volume unmuted || notify-send '🎙️ Microphone unmuted'
  fi
}

main() {
  toggle_mic_mute
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
