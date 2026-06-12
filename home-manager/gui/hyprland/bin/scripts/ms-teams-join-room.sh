#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

# BROWSER=firefox
BROWSER=chromium

# Edge Stack
HOME_ROOM_URL=$(ms-teams url "home room")
TITLE="$(ms-teams title "home room") | Microsoft Teams"

case "$1" in
  https:*)
    URL="$1"
    ;;
  *)
    URL="$HOME_ROOM_URL"
    ;;
esac

# NOTE use "workspace 2 silent;" if you don't want the app to get focused
# when started
bash -x ./browser-run-or-raise.sh \
  --rule '[workspace 2; fullscreenstate;]' \
  --browser "${BROWSER[*]}" \
  --new-window \
  --title "$TITLE" \
  --url "$URL"
