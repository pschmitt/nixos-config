#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--host HOSTNAME] [--remote-path PATH]"
}

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
    if [[ "${HOSTNAME:-$(hostname)}" == "$REMOTE_HOST" ]]
    then
      cp "${REMOTE_PATH}/${font}" "$font"
    else
      scp "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${font}" "$font"
    fi
  done

  check_fonts
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  REMOTE_USER=${REMOTE_USER:-github-actions}
  REMOTE_HOST=${REMOTE_HOST:-rofl-02}
  REMOTE_PATH=${REMOTE_PATH:-./src}

  while [[ -n "$*" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --user*|--remote-user*|-u)
        REMOTE_USER="$2"
        shift 2
        ;;
      --host|--hostname|--remote-host*|-H)
        REMOTE_HOST="$2"
        shift 2
        ;;
      --remote-path|-p)
        REMOTE_PATH="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if check_fonts --quiet --status 2>/dev/null
  then
    echo -e "\e[32m✅All font archives present and accounted for"
    exit 0
  fi

  fetch_fonts
fi
