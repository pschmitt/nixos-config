#!/usr/bin/env bash

REMOTE_HOST=rofl-01
REMOTE_PATH=/srv/nextcloud/data/nextcloud/pschmitt/files/Fonts

list_fonts() {
  awk '{ print $2 }' ./sha256sum.txt
}

check_fonts() {
  sha256sum -c ./sha256sum.txt "$@"
}

fetch_fonts() {
  local font

  for font in $(list_fonts)
  do
    if [[ "$HOSTNAME" == "$REMOTE_HOST" ]]
    then
      cp "${REMOTE_PATH}/${font}" "$font"
    else
      scp "${REMOTE_HOST}:${REMOTE_PATH}/${font}" "$font"
    fi
  done

  check_fonts
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if check_fonts --quiet --status 2>/dev/null
  then
    echo -e "\e[32m✅All font archives present and accounted for"
    exit 0
  fi

  fetch_fonts
fi
