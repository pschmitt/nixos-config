#!/usr/bin/env bash
# Waybar custom/screencast module.
#
# State comes from screencast-state(1), which reads the PipeWire graph
# directly, so this no longer depends on the xdg-portal-screencast-watcher
# service and its /tmp/screencast.json state file.

screencast_state() {
  screencast-state --json 2>/dev/null
}

format() {
  local state icon text alt tooltip apps
  local icon_on=''

  state="$(screencast_state)"

  if jq -e '.active' <<< "$state" &> /dev/null
  then
    apps="$(jq -r '.apps | join(", ")' <<< "$state")"
    icon="$icon_on"
    text='<span foreground="#e27978" font-weight="bold">SCREENCASTING</span>'
    tooltip="Screencasting with $apps"
    alt=on
  else
    icon=""
    text=""
    tooltip="Not screencasting"
    alt=off
  fi

  jq -ernc --arg app screencast --arg icon "$icon" \
    --arg class custom-screencast --arg alt "$alt" \
    --arg text "$text" --arg tooltip "$tooltip" \
    '{
      "text": (if $text != "" then ($icon + " " + $text) else $icon end),
      "alt": $alt,
      "class": $class,
      "tooltip": $tooltip
    }'
}

main() {
  case "${1:-}" in
    format)
      format
      ;;
    *)
      printf 'Usage: %s format\n' "$(basename "$0")" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
