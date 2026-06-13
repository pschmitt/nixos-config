#!/usr/bin/env bash

# Check if we are being invoked by waybar
case "$1" in
  format)
    echo '{"text": "📋", "alt": "clipboard", "class": "custom-clipboard", "tooltip": "Clipbard History powered by cliphist. Click me!" }'
    exit 0
    ;;
esac

walker --close 2>/dev/null || true

CLIP_HISTORY="$(cliphist list | head -n "${HIST_COUNT:-100}")"

# Strip leading cliphist IDs before presenting to walker, then map back.
res="$(
  sed -r 's#^[0-9]+\s+##' <<< "$CLIP_HISTORY" | \
  walker --dmenu -p "󰅍 Clipboard history"
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
