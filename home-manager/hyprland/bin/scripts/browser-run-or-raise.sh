#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--title TITLE] URL"
}

find_tab() {
  [[ -z $* ]] && return 0
  "$HOME/bin/zhj" "browser::tabs -o id '$*'"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --browser)
        BROWSER="$2"
        shift 2
        ;;
      --title)
        TAB_TITLE="$2"
        shift 2
        ;;
      --url)
        URL="$2"
        shift 2
        ;;
      --alt)
        ALT_URL="$2"
        shift 2
        ;;
      --new-window)
        EXTRA_ARGS=(--new-window)
        # NEW_WINDOW=1
        shift
        ;;
      --rule*)
        RULES="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  TAB_TITLE="${TAB_TITLE:-$URL}"
  BROWSER=${BROWSER:-firefox}

  if [[ -z "$URL" ]]
  then
    usage >&2
    exit 2
  fi

  echo "$0 - title: \"$TAB_TITLE\" - url: \"$URL\" - alt: \"$ALT_URL\"" >&2

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  source run-or-raise.sh

  BROWSER_BIN=$(cut -d' ' -f1 <<< "$BROWSER")
  # NOTE google-chrome-stable's application name is google-chrome
  case "$BROWSER_BIN" in
    google-chrome*|chromium*)
      BROWSER_BIN=google-chrome
      ;;
  esac

  APP_ADDRESS="$(app_address "${BROWSER_BIN}")"
  if [[ -z "$APP_ADDRESS" ]]
  then
    hyprctl dispatch exec -- "${BROWSER}" "$URL"
    sleep 2
  fi

  mapfile -t TABS < <(find_tab "$TAB_TITLE"; find_tab "$ALT_URL")

  if [[ "${#TABS[@]}" -gt 0 ]]
  then
    {
      echo "Matching tabs:"
      for tab in "${TABS[@]}"
      do
        echo "-  $tab"
      done
    }

    echo "Activating first matching tab"
    brotab activate --focused "$(awk '{print $1}' <<< "${TABS[0]}")"
    exit "$?"
  fi

  # append space so that we do not mess up the command
  [[ -n "$RULES" ]] && RULES="${RULES} "
  hyprctl dispatch exec -- "${RULES}${BROWSER}" "${EXTRA_ARGS[@]}" "$URL"
fi
