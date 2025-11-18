#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: fetch-fonts.sh [--base-url URL] [--username USER] [--password PASS] [--auth USER:PASS]

Environment variables:
  BLOBS_URL         Override the download endpoint (default: https://blobs.brkn.lol/private/fonts)
  BLOBS_BASIC_AUTH  Provide HTTP basic auth credentials directly (USER:PASS)
  BLOBS_USERNAME    Username part of the credentials
  BLOBS_PASSWORD    Password part of the credentials
USAGE
}

list_fonts() {
  awk '{ print $2 }' ./sha256sum.txt
}

font_checksum() {
  local font="$1"
  awk -v font="$font" '$2 == font { print $1; exit 0 }' ./sha256sum.txt
}

font_is_valid() {
  local font="$1"
  local checksum="$2"

  [[ -f "$font" ]] || return 1

  if printf "%s  %s\n" "$checksum" "$font" | sha256sum --status --check -
  then
    return 0
  fi

  return 1
}

check_fonts() {
  sha256sum -c ./sha256sum.txt "$@"
}

fetch_fonts() {
  local font checksum tmp_file
  local -a curl_args=(
    --fail
    --location
    --retry 5
    --retry-delay 2
    --silent
    --show-error
  )

  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    echo "BLOBS_BASIC_AUTH is required to download private fonts" >&2
    return 1
  fi

  curl_args+=(
    --user "$BLOBS_BASIC_AUTH"
  )

  for font in $(list_fonts)
  do
    checksum="$(font_checksum "$font")"
    if [[ -z "$checksum" ]]
    then
      echo "No checksum found for $font" >&2
      return 1
    fi

    if font_is_valid "$font" "$checksum"
    then
      continue
    fi

    tmp_file="$(mktemp "${font}.XXXXXX")"
    if ! curl "${curl_args[@]}" \
      "${BLOBS_URL%/}/${font}" \
      --output "$tmp_file"
    then
      rm -f "$tmp_file"
      return 1
    fi

    mv "$tmp_file" "$font"
  done

  check_fonts
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  BLOBS_URL=${BLOBS_URL:-https://blobs.brkn.lol/private/fonts}
  BLOBS_USERNAME=${BLOBS_USERNAME:-}
  BLOBS_PASSWORD=${BLOBS_PASSWORD:-}
  BLOBS_AUTH=${BLOBS_AUTH:-}

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --base-url)
        BLOBS_URL="$2"
        shift 2
        ;;
      --username)
        BLOBS_USERNAME="$2"
        shift 2
        ;;
      --password)
        BLOBS_PASSWORD="$2"
        shift 2
        ;;
      --auth)
        BLOBS_AUTH="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    if [[ -n "$BLOBS_AUTH" ]]
    then
      BLOBS_BASIC_AUTH="$BLOBS_AUTH"
    elif [[ -n "$BLOBS_USERNAME" || -n "$BLOBS_PASSWORD" ]]
    then
      if [[ -z "$BLOBS_USERNAME" || -z "$BLOBS_PASSWORD" ]]
      then
        echo "--username and --password must be provided together" >&2
        exit 64
      fi

      BLOBS_BASIC_AUTH="${BLOBS_USERNAME}:${BLOBS_PASSWORD}"
    fi
  fi

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if check_fonts --quiet --status 2>/dev/null
  then
    echo -e "\e[32m✅All font archives present and accounted for\e[0m"
    exit 0
  fi

  fetch_fonts
fi
