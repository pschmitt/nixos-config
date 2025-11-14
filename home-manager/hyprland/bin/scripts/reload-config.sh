#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  hyprctl notify 0 5000 'rgb(ffa500)' "Reloading..."
  hyprctl reload

  (
    sleep 3
    # TODO This seems to mess up the LG monitor for a little while.shikane
    # Race condition?
    # shikane --oneshot
    pkill -USR2 waybar
  ) &
fi
