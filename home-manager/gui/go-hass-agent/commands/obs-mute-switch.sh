#!/usr/bin/env bash
# go-hass-agent command switch for voice mute, matching the keyboard shortcuts.
case "${1:-}" in
  ON)
    obs-control mute
    ;;
  OFF)
    obs-control unmute
    ;;
  *)
    if obs-control mic-is-muted
    then
      echo ON
    else
      echo OFF
    fi
    ;;
esac

# vim: set ft=sh et ts=2 sw=2 :
