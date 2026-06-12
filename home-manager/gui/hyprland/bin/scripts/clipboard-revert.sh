#!/usr/bin/env bash
# Swap the clipboard to the previous (2nd-most-recent) cliphist entry.
# Replaces the zhj `clipboard::revert` helper.

notify=
case "${1:-}" in
  -n | --notify) notify=1 ;;
esac

item="$(cliphist list | sed -n 2p | cliphist decode)"
[[ -z "$item" ]] && exit 1

wl-copy <<< "$item"
rc=$?

if [[ -n "$notify" ]]
then
  if [[ "$rc" -eq 0 ]]
  then
    notify-send --app-name clipboard-revert \
      "$(printf '%s\n%s' '📋 Swapped clipboard content' "$item")"
  else
    notify-send --app-name clipboard-revert "🔴 Failed to swap clipboard content"
  fi
fi

exit "$rc"
