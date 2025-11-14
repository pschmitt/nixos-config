#!/usr/bin/env bash

hyprctl::current-workspace-clients () {
  local ws_id
  ws_id=$(hyprctl -j activeworkspace | jq -er .id)

  hyprctl -j clients | jq -er --argjson ws_id "$ws_id" '
    [.[] | select(.workspace.id == $ws_id)]
  '
}

hyprctl::client-count() {
  hyprctl::current-workspace-clients | jq -r 'length'
}

hyprctl::move-window() {
  local direction="$1"
  hyprctl dispatch movewindow "$direction"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  DIRECTION="$1"
  RES=$(hyprctl::move-window "$DIRECTION")

  case "$RES" in
    *Nowhere*)
      CLIENT_COUNT=$(hyprctl::client-count)
      if [[ "$CLIENT_COUNT" -gt 1 ]]
      then
        hyprctl dispatch togglesplit
        hyprctl dispatch movewindow "$DIRECTION"
      fi
      ;;
  esac
fi

