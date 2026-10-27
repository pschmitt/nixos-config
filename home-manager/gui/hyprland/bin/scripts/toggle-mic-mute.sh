#!/usr/bin/env bash

set -euo pipefail

toggle_mic_mute() {
  if noctalia msg plugin pschmitt/mic-state:status all toggle_mute
  then
    return 0
  fi

  noctalia msg mic-mute
}

main() {
  toggle_mic_mute
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
