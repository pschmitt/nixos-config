#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  killall slurp

  # freeze motherfucker!
  # shellcheck disable=SC2016
  wayfreeze  --before-freeze-timeout 10 --before-freeze-cmd '
    img=$(mktemp --suffix=.png)

    if ! grim -g "$(slurp)" "$img"
    then
      rm -f "$img"
      killall wayfreeze
      exit 1
    fi

    # unfreeze immediately
    killall wayfreeze &

    # spawn swappy via systemd-run so it is not tied to this shell
    systemd-run --user --quiet --collect swappy -f "$img"

    # cleanup after a short delay (lets swappy open the file first)
    ( sleep 2; rm -f "$img" ) &
  '
fi
