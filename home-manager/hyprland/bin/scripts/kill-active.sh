#!/usr/bin/env bash

# Kill active window
hyprctl dispatch killactive

# Disable tab/grouping if we just killed the previous-to-last window
# in a group (ie there's only one left)
if hyprctl activewindow -j | jq -er '(.grouped | length) == 1'
then
  hyprctl dispatch togglegroup
fi
