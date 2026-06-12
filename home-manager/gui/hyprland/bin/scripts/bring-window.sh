#!/usr/bin/env bash
# Focus a window by class (and optionally fullscreen it). Replaces the zhj
# `hyprctl::bring-window` helper. Simplified: focuses the window's workspace
# rather than moving that workspace onto the current monitor.

fullscreen=
while [[ $# -gt 0 ]]
do
  case "$1" in
    -f | --fullscreen) fullscreen=1; shift ;;
    -h | --help) echo "usage: $0 [-f] APP" >&2; exit 0 ;;
    *) break ;;
  esac
done

app="${1:-}"
if [[ -z "$app" ]]
then
  echo "usage: $0 [-f] APP" >&2
  exit 2
fi

read -r addr is_fs < <(hyprctl -j clients \
  | jq -er --arg c "$app" '[.[] | select(.class | test($c; "i"))][0] | "\(.address) \(.fullscreen)"' 2>/dev/null)

if [[ -z "$addr" || "$addr" == "null" ]]
then
  notify-send --app-name bring-window "No window found for $app"
  exit 1
fi

hyprctl dispatch focuswindow "address:$addr"

if [[ -n "$fullscreen" && "$is_fs" != "true" && "$is_fs" != "1" && "$is_fs" != "2" ]]
then
  hyprctl dispatch fullscreen
fi
