# soundboard — Nix-native replacement for the zhj-backed soundboard:: zsh
# helpers. Plays local sound files into the Meeting Microphone: the stream is
# tagged meeting-mic.feed and linked by the meeting-mic WirePlumber script.
# A separate playback stream makes clips audible locally without mic sidetone.
#
# Scope vs the zsh original: local playback + routing only. The --tts,
# kitchen (Home Assistant), --remote (scp) and download (yt-dlp) paths are
# intentionally not ported.

shopt -s nullglob

SOUNDBOARD_DIR="${SOUNDBOARD_DIR:-${HOME}/Music/Soundboard}"
SOUNDBOARD_VOLUME="${SOUNDBOARD_VOLUME:-70}" # percent

# Routing is declared in Home Manager. Keep this command for existing callers.
connect() {
  return 0
}

# ── Sounds ─────────────────────────────────────────────────────────────────
list_sounds() {
  local filter="${1:-.}" f base
  for f in "$SOUNDBOARD_DIR"/*
  do
    [[ -e "$f" ]] || continue
    base="${f##*/}" # filename
    base="${base%%.*}" # strip extension (from first dot, as the original did)
    if grep -qE -- "$filter" <<< "$base"
    then
      echo "$base"
    fi
  done
}

resolve_sound() {
  local name="$1"
  if [[ -f "$name" ]]
  then
    echo "$name"
    return 0
  fi
  local matches=("$SOUNDBOARD_DIR"/*"$name"*)
  if [[ "${#matches[@]}" -eq 0 ]]
  then
    return 1
  fi
  echo "${matches[0]}"
}

sb_play() {
  local name="$1" file volume
  if [[ -z "$name" ]]
  then
    echo "Usage: soundboard play SOUND" >&2
    return 2
  fi

  if ! file="$(resolve_sound "$name")"
  then
    echo "No sound found for '$name'" >&2
    list_sounds >&2
    return 1
  fi

  connect

  volume="$(awk -v v="$SOUNDBOARD_VOLUME" 'BEGIN { print v / 100.0 }')"
  pw-play --volume "$volume" \
    --properties '{ node.autoconnect = false, meeting-mic.feed = true }' \
    "$file" &
  local meeting_playback=$!
  pw-play --volume "$volume" "$file"
  wait "$meeting_playback"
}

sb_random() {
  if [[ "$#" -eq 0 ]]
  then
    echo "Usage: soundboard random SOUND [SOUND...]" >&2
    return 2
  fi
  local idx=$(( RANDOM % $# ))
  local -a choices=("$@")
  sb_play "${choices[$idx]}"
}

sb_stop() {
  killall pw-play 2>/dev/null || true
}

case "${1:-}" in
  play)
    shift
    sb_play "${1:-}"
    ;;
  random)
    shift
    sb_random "$@"
    ;;
  list)
    shift
    list_sounds "${1:-}"
    ;;
  stop)
    shift
    sb_stop
    ;;
  connect)
    shift
    connect
    ;;
  "" | -h | --help | help)
    echo "Usage: soundboard {play SOUND|random SOUND...|list [FILTER]|stop|connect}" >&2
    [[ "${1:-}" == "" ]] && exit 2 || exit 0
    ;;
  *)
    echo "Unknown command: $1" >&2
    exit 2
    ;;
esac

# vim: set ft=sh et ts=2 sw=2 :
