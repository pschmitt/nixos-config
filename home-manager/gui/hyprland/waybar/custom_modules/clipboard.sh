#!/usr/bin/env bash

kill_wofi() {
  killall wofi
  killall .wofi-wrapped # nixos
}

# Check if we are being invoked by waybar
case "$1" in
  format)
    echo '{"text": "📋", "alt": "clipboard", "class": "custom-clipboard", "tooltip": "Clipbard History powered by cliphist. Click me!" }'
    exit 0
    ;;
esac

kill_wofi &>/dev/null

# Show wofi and update clipboard when entry gets selected
CLIP_HISTORY="$(cliphist list | head -n "${HIST_COUNT:-100}")"

# FIXME Once --with-nth is implemented in wofi we should no longer need
# to hide the clipboard entry IDs manually
# https://todo.sr.ht/~scoopta/wofi/126

# Show wofi clipboard history, without leading IDs
res="$(
  sed -r 's#^[0-9]+\s+##' <<< "$CLIP_HISTORY" | \
  wofi --show=dmenu --insensitive --prompt "󰅍 Clipboard history")"

if [[ -z "$res" ]]
then
  echo "Nothing selected" >&2
  exit 1
fi

# Get the entire line
if ! res="$(grep --color=never --max-count=1 \
  -- "${res}\$" <<< "$CLIP_HISTORY")"
then
  echo "Failed to find full line matching $res in cliphist" >&2
  # copy whatever we have
  echo -n "$res" | wl-copy
  exit 1
fi

echo -n "$res" | cliphist decode | wl-copy
