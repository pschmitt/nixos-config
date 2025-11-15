#!/usr/bin/env bash

set -euo pipefail

schema="org.gnome.desktop.a11y.applications"
key="screen-keyboard-enabled"

current_state="$(gsettings get "${schema}" "${key}")"

if [[ "${current_state}" == "true" ]]; then
  gsettings set "${schema}" "${key}" false
  pkill -x squeekboard >/dev/null 2>&1 || true
else
  gsettings set "${schema}" "${key}" true
  if ! pgrep -x squeekboard >/dev/null 2>&1; then
    setsid squeekboard >/dev/null 2>&1 &
  fi
fi
