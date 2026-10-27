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

  # Noctalia's native mic OSD follows the default meeting mix, which remains
  # unmuted for soundboard playback. The mic-state bar widget tracks the voice
  # source and updates independently.
}

main() {
  toggle_mic_mute
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
