#!/usr/bin/env bash
# go-hass-agent command switch for microphone mute.
# Called with ON/OFF to set state, or no arg to query.
case "${1:-}" in
    ON)  obs-control mute ;;
    OFF) obs-control unmute ;;
    *)
        if pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -qi yes; then
            echo ON
        else
            echo OFF
        fi
        ;;
esac
