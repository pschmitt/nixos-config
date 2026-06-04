#!/usr/bin/env bash

has_monitor_in_direction() {
  local direction="$1"
  local current_monitor cx cy

  current_monitor=$(hyprctl -j activeworkspace | jq -r .monitor)

  read -r cx cy < <(
    hyprctl -j monitors | jq -r --arg mon "$current_monitor" '
      .[] | select(.name == $mon) | "\(.x) \(.y)"
    '
  )

  hyprctl -j monitors | jq -er \
    --argjson cx "$cx" --argjson cy "$cy" \
    --arg dir "$direction" '
    .[] | select(
      if $dir == "l" then .x < $cx
      elif $dir == "r" then .x > $cx
      elif $dir == "u" then .y < $cy
      elif $dir == "d" then .y > $cy
      else false end
    ) | .name
  ' > /dev/null 2>&1
}

# Returns true if a window on the same workspace has its edge directly touching
# (within gap tolerance) the active window's edge in the given direction, and
# their ranges on the perpendicular axis overlap.
has_window_on_workspace_in_direction() {
  local direction="$1"
  local ws_id ax ay aw ah
  local gap=50

  ws_id=$(hyprctl -j activeworkspace | jq -r .id)
  read -r ax ay aw ah < <(
    hyprctl -j activewindow | jq -r '"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"'
  )

  hyprctl -j clients | jq -er \
    --argjson ws_id "$ws_id" \
    --argjson ax "$ax" --argjson ay "$ay" \
    --argjson aw "$aw" --argjson ah "$ah" \
    --argjson gap "$gap" \
    --arg dir "$direction" '
    .[] | select(.workspace.id == $ws_id) |
    .at[0] as $bx | .at[1] as $by | .size[0] as $bw | .size[1] as $bh |
    ($ax + $aw) as $ar | ($ay + $ah) as $ab |
    ($bx + $bw) as $br | ($by + $bh) as $bb |
    select(
      if $dir == "l" then
        ($br >= ($ax - $gap)) and ($br <= ($ax + $gap)) and
        ($bb > $ay) and ($by < $ab)
      elif $dir == "r" then
        ($bx >= ($ar - $gap)) and ($bx <= ($ar + $gap)) and
        ($bb > $ay) and ($by < $ab)
      elif $dir == "u" then
        ($bb >= ($ay - $gap)) and ($bb <= ($ay + $gap)) and
        ($br > $ax) and ($bx < $ar)
      elif $dir == "d" then
        ($by >= ($ab - $gap)) and ($by <= ($ab + $gap)) and
        ($br > $ax) and ($bx < $ar)
      else false end
    ) | .address
  ' > /dev/null 2>&1
}

# Returns true if another workspace window is directly adjacent perpendicular to
# the given direction — i.e. directly above/below for l/r, directly left/right
# for u/d. Indicates a split that togglesplit can flatten.
has_perpendicular_split_sibling() {
  local direction="$1"
  local ws_id win_addr ax ay aw ah
  local gap=50

  ws_id=$(hyprctl -j activeworkspace | jq -r .id)
  read -r win_addr ax ay aw ah < <(
    hyprctl -j activewindow | jq -r '"\(.address) \(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"'
  )

  hyprctl -j clients | jq -er \
    --argjson ws_id "$ws_id" \
    --argjson ax "$ax" --argjson ay "$ay" \
    --argjson aw "$aw" --argjson ah "$ah" \
    --arg addr "$win_addr" \
    --argjson gap "$gap" \
    --arg dir "$direction" '
    .[] | select(.workspace.id == $ws_id) | select(.address != $addr) |
    .at[0] as $bx | .at[1] as $by | .size[0] as $bw | .size[1] as $bh |
    ($ax + $aw) as $ar | ($ay + $ah) as $ab |
    ($bx + $bw) as $br | ($by + $bh) as $bb |
    select(
      if ($dir == "l" or $dir == "r") then
        (($bb >= ($ay - $gap) and $bb <= ($ay + $gap)) or
         ($by >= ($ab - $gap) and $by <= ($ab + $gap))) and
        ($br > $ax) and ($bx < $ar)
      elif ($dir == "u" or $dir == "d") then
        (($br >= ($ax - $gap) and $br <= ($ax + $gap)) or
         ($bx >= ($ar - $gap) and $bx <= ($ar + $gap))) and
        ($bb > $ay) and ($by < $ab)
      else false end
    ) | .address
  ' > /dev/null 2>&1
}

move_window() {
  local direction="$1"

  if has_window_on_workspace_in_direction "$direction"
  then
    hyprctl dispatch "hl.dsp.window.swap({ direction = '$direction' })"
    return
  fi

  if ! has_monitor_in_direction "$direction"
  then
    local geom_before geom_after
    geom_before=$(hyprctl -j activewindow | jq -r '"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
    hyprctl dispatch "hl.dsp.window.move({ direction = '$direction' })"
    geom_after=$(hyprctl -j activewindow | jq -r '"\(.at[0]) \(.at[1]) \(.size[0]) \(.size[1])"')
    [[ "$geom_before" != "$geom_after" ]] && return
  fi

  if has_perpendicular_split_sibling "$direction"
  then
    local x_before y_before x_after y_after
    read -r x_before y_before < <(hyprctl -j activewindow | jq -r '"\(.at[0]) \(.at[1])"')
    hyprctl dispatch "hl.dsp.layout('togglesplit')"
    read -r x_after y_after < <(hyprctl -j activewindow | jq -r '"\(.at[0]) \(.at[1])"')
    case "$direction" in
      l) [[ "$x_after" -gt "$x_before" ]] && hyprctl dispatch "hl.dsp.window.swap({ direction = 'l' })" ;;
      r) [[ "$x_after" -lt "$x_before" ]] && hyprctl dispatch "hl.dsp.window.swap({ direction = 'r' })" ;;
      u) [[ "$y_after" -gt "$y_before" ]] && hyprctl dispatch "hl.dsp.window.swap({ direction = 'u' })" ;;
      d) [[ "$y_after" -lt "$y_before" ]] && hyprctl dispatch "hl.dsp.window.swap({ direction = 'd' })" ;;
    esac
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  move_window "$1"
fi

# vim: set ts=2 sw=2 et:
