#!/usr/bin/env bash

# Share the Noctalia controller when installed; retain a standalone fallback.
if command -v touch-keyboard >/dev/null 2>&1
then
  exec touch-keyboard toggle
fi

set -euo pipefail
schema="org.gnome.desktop.a11y.applications"
key="screen-keyboard-enabled"
pattern='^(squeekboard|\.squeekboard-wr)$'
if pgrep -u "$UID" -x "$pattern" >/dev/null
then
  gsettings set "$schema" "$key" false
  pkill -u "$UID" -x "$pattern" || true
else
  gsettings set "$schema" "$key" true
  setsid squeekboard </dev/null >/dev/null 2>&1 &
fi

# vim: set ft=sh et ts=2 sw=2 :
