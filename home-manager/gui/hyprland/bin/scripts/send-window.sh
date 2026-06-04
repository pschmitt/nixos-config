#!/usr/bin/env bash

monitor_in_direction() {
  local direction="$1"
  local current_monitor cx cy cw ch

  current_monitor=$(hyprctl -j activeworkspace | jq -r .monitor)

  read -r cx cy cw ch < <(
    hyprctl -j monitors | jq -r --arg mon "$current_monitor" '
      .[] | select(.name == $mon) | "\(.x) \(.y) \(.width) \(.height)"
    '
  )

  local cr=$((cx + cw))
  local cb=$((cy + ch))

  hyprctl -j monitors | jq -r \
    --arg mon "$current_monitor" \
    --argjson cx "$cx" --argjson cy "$cy" \
    --argjson cr "$cr" --argjson cb "$cb" \
    --arg dir "$direction" '
    [.[] | select(.name != $mon) | select(
      if $dir == "l" then .x < $cx
      elif $dir == "r" then .x >= $cr
      elif $dir == "u" then .y < $cy
      elif $dir == "d" then .y >= $cb
      else false end
    )] |
    if $dir == "l" then sort_by(-.x)
    elif $dir == "r" then sort_by(.x)
    elif $dir == "u" then sort_by(-.y)
    elif $dir == "d" then sort_by(.y)
    else . end |
    first | .name // empty
  '
}

send_window() {
  local direction="$1"
  local target_monitor
  target_monitor=$(monitor_in_direction "$direction")

  if [[ -n "$target_monitor" ]]
  then
    local win_addr
    win_addr=$(hyprctl -j activewindow | jq -r .address)
    hyprctl dispatch "hl.dsp.window.move({ monitor = '$target_monitor' })"
    hyprctl dispatch "hl.dsp.focus({ window = 'address:$win_addr' })"
  else
    case "$direction" in
      l|u)
        hyprctl dispatch "hl.dsp.window.move({ workspace = '-1' })"
        ;;
      r|d)
        hyprctl dispatch "hl.dsp.window.move({ workspace = '+1' })"
        ;;
    esac
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  send_window "$1"
fi

# vim: set ts=2 sw=2 et:
