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

# Show wofi clipboard history, without leading IDs. Disable markup so we don't
# have to escape user data (ampersands, angle brackets, etc.).
res="$(
  sed -r 's#^[0-9]+\s+##' <<< "$CLIP_HISTORY" | \
  wofi --show=dmenu --insensitive --allow-markup=false --prompt "󰅍 Clipboard history"
)"

if [[ -z "$res" ]]
then
  echo "Nothing selected" >&2
  exit 1
fi

# Get the entire line by matching the stripped text exactly (no regex), so
# special characters don't break the lookup.
full_line="$(awk -v sel="$res" '
  {
    orig = $0
    txt = $0
    sub(/^[0-9]+[[:space:]]+/, "", txt)
    if (txt == sel) {
      print orig
      exit
    }
  }
' <<< "$CLIP_HISTORY")"
if [[ -z "$full_line" ]]
then
  echo "Failed to find full line matching $res in cliphist" >&2
  # copy whatever we have
  echo -n "$res" | wl-copy
  exit 1
fi

echo -n "$full_line" | cliphist decode | wl-copy
