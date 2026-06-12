# obs-control — Nix-native replacement for the zhj-backed ~/bin/obs.zsh
# dispatcher. Drives OBS Studio (scenes, filters, overlay items, replay,
# emoji reactions), microphone mute state, and the Insta360 webcam, talking
# to obs-websocket via obs-cli.
#
# Password resolution (no rbw/keyring): OBS_API_PASSWORD env (set by the
# go-hass-agent service) -> $OBS_PASSWORD_FILE -> the obs-websocket.password
# file under the OBS config dir.
#
# Soundboard sound effects (thumbs-up/down) go through the `soundboard`
# package (a runtimeInput).

DEFAULT_SCENE="📹 Webcam"
WEBCAM_NAME="Insta360 Link"
OBS_SOURCE_NAME="Webcam"
MIC_OFF_ITEM="Microphone off"
NOTIFY_ICON="${HOME}/Pictures/Icons/obs.png"

ensure_obs_env() {
  : "${OBS_API_HOST:=localhost}"
  : "${OBS_API_PORT:=6277}"
  export OBS_API_HOST OBS_API_PORT

  if [[ -z "${OBS_API_PASSWORD:-}" ]]
  then
    local file="${OBS_PASSWORD_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/obs-studio/obs-websocket.password}"
    if [[ -r "$file" ]]
    then
      OBS_API_PASSWORD="$(< "$file")"
      export OBS_API_PASSWORD
    fi
  fi
}

obscli() {
  obs-cli "$@"
}

notify() {
  [[ -n "${NO_NOTIFICATION:-}" ]] && return 0
  # Match the original obs.zsh OSD styling: the osd-top-center category is
  # themed by mako, and the synchronous hint makes rapid notifications
  # replace one another instead of stacking.
  notify-send \
    --app-name obs.zsh \
    --hint "string:x-canonical-private-synchronous:obs.zsh" \
    --category osd-top-center \
    --icon "$NOTIFY_ICON" \
    "$1" 2>/dev/null || true
}

# ── Scenes ───────────────────────────────────────────────────────────────
current_scene() {
  obscli scene current
}

resolve_scene() {
  local query="$1"

  obscli scene list --json | jq -er --arg name "$query" '
    def normalize:
      ascii_downcase
      | sub("^[^[:alnum:]]+"; "")
      | sub("^[[:space:]]+"; "");

    ($name | normalize) as $query
    | [
        .[]
        | .sceneName as $scene
        | ($scene | normalize) as $normalized
        | select(
            $normalized == $query
            or ($normalized | startswith($query))
            or ($normalized | contains($query))
          )
        | {
            sceneName: $scene,
            score: (
              if $normalized == $query
              then [0, 0, ($normalized | length), $normalized]
              elif ($normalized | startswith($query))
              then [1, (($normalized | length) - ($query | length)), ($normalized | length), $normalized]
              else [2, ($normalized | length), 0, $normalized]
              end
            )
          }
      ]
    | sort_by(.score)
    | first
    | .sceneName
  '
}

switch_scene() {
  local scene
  if ! scene="$(resolve_scene "$1")" || [[ -z "$scene" || "$scene" == "null" ]]
  then
    echo "No scene matching \"$1\" found." >&2
    return 1
  fi

  obscli scene switch "$scene"
}

# ── Filters ──────────────────────────────────────────────────────────────
filter_toggle() {
  obscli filter toggle "$1" "$2"
}

filter_is_enabled() {
  obscli --quiet filter status "$1" "$2"
}

filter_disable() {
  obscli filter disable "$1" "$2"
}

# ── Microphone / PulseAudio ────────────────────────────────────────────────
# Non-monitor sources, one name per line.
list_real_sources() {
  pactl list short sources | awk -F'\t' '$2 !~ /\.monitor/ { print $2 }'
}

default_source_is_muted() {
  pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -qi 'yes'
}

mute_all_sources() {
  local source
  while IFS= read -r source
  do
    [[ -n "$source" ]] && pactl set-source-mute "$source" 1 || true
  done < <(list_real_sources)
}

unmute_all_sources() {
  local source
  while IFS= read -r source
  do
    [[ -n "$source" ]] && pactl set-source-mute "$source" 0 || true
  done < <(list_real_sources)
}

# Mirror the OBS "Microphone off" overlay to the current mute state.
sync_mic_overlay() {
  if default_source_is_muted
  then
    obscli item -s "$DEFAULT_SCENE" show "$MIC_OFF_ITEM" 2>/dev/null || true
  else
    obscli item -s "$DEFAULT_SCENE" hide "$MIC_OFF_ITEM" 2>/dev/null || true
  fi
}

mute_mic() {
  mute_all_sources
  sync_mic_overlay
  notify "🔇 Muted"
}

unmute_mic() {
  unmute_all_sources
  sync_mic_overlay
  notify "🎤 Unmuted"
}

toggle_mute() {
  if default_source_is_muted
  then
    unmute_all_sources
  else
    mute_all_sources
  fi
  sync_mic_overlay
}

# ── Webcam (Insta360 via v4l2) ─────────────────────────────────────────────
v4l2_device() {
  local dev
  for dev in /sys/class/video4linux/*
  do
    if grep -qi "$1" "$dev/name" 2>/dev/null
    then
      echo "/dev/$(basename "$dev")"
      return 0
    fi
  done
  return 1
}

v4l2_device_by_id() {
  local target dev
  target="$(v4l2_device "$1")" || return 1
  for dev in /dev/v4l/by-id/*
  do
    if [[ "$(realpath "$dev")" == "$target" ]]
    then
      echo "$dev"
      return 0
    fi
  done
  echo "$target"
}

camera_set_ceiling() {
  local dev
  dev="$(v4l2_device "$WEBCAM_NAME")" || return 0
  v4l2-ctl --device "$dev" \
    --set-ctrl pan_absolute=-262800 \
    --set-ctrl tilt_absolute=221040 \
    --set-ctrl zoom_absolute=400 || true
}

# Point the OBS "Webcam" input at the Insta360 device, then reset its framing.
fix_webcam() {
  local dev current
  dev="$(v4l2_device "$WEBCAM_NAME")" || return 0

  current="$(obscli input show "$OBS_SOURCE_NAME" device_id 2>/dev/null || true)"
  if [[ "$current" == "$dev" ]]
  then
    # Force a path change so OBS picks up the device again.
    dev="$(v4l2_device_by_id "$WEBCAM_NAME")"
  fi
  obscli input set "$OBS_SOURCE_NAME" device_id "$dev" 2>/dev/null || true

  local cam_dev
  cam_dev="$(v4l2_device "$WEBCAM_NAME")" || return 0
  v4l2-ctl --device "$cam_dev" \
    --set-ctrl pan_absolute=18514 \
    --set-ctrl tilt_absolute=-53365 \
    --set-ctrl zoom_absolute=100 || true
  # OBS may reset framing from the source properties; set it once more.
  sleep 2
  v4l2-ctl --device "$cam_dev" \
    --set-ctrl pan_absolute=18514 \
    --set-ctrl tilt_absolute=-53365 \
    --set-ctrl zoom_absolute=100 || true
}

# ── Emoji reactions ────────────────────────────────────────────────────────
emoji_react() {
  local emoji="$1"
  local file="${XDG_DATA_HOME:-${HOME}/.local/share}/obs-studio/emoji.txt"
  local scene="$MIC_OFF_ITEM"
  local item="Emoji Reaction"

  scene="$(current_scene)"

  if [[ -z "$emoji" ]]
  then
    emoji="$(emoji-fzf preview --prepend \
      | sed -nr 's#([^\s+])\s+(.+)#\1 <span foreground="gray">\2</span>#p' \
      | wofi --show dmenu -i --allow-markup --prompt "📹 OBS Studio Emoji reaction" \
      | cut -d ' ' -f 1 \
      | tr -d '\n')"
  fi

  [[ -z "$emoji" ]] && return 1

  mkdir -p "$(dirname "$file")"
  printf '%s' "$emoji" > "$file"

  obscli item -s "$scene" show "$item" 2>/dev/null || true
  sleep 5
  obscli item -s "$scene" hide "$item" 2>/dev/null || true
}

soundboard_play() {
  soundboard play "$1" 2>/dev/null || true
}

# ── Dispatch ───────────────────────────────────────────────────────────────
ensure_obs_env

verb="${1:-}"
[[ $# -gt 0 ]] && shift

case "$verb" in
  mute)
    mute_mic
    ;;
  unmute)
    unmute_mic
    ;;
  toggle-mute)
    toggle_mute
    ;;
  update | sync)
    NO_NOTIFICATION=1 sync_mic_overlay
    ;;
  toggle-freeze | freeze | f)
    filter_toggle "Webcam" "Freeze"
    if filter_is_enabled "Webcam" "Freeze"
    then
      notify "🥶 Enabled Freeze filter"
    else
      notify "❌ Disabled Freeze filter"
    fi
    ;;
  replay | loop)
    obscli trigger ReplaySource.Replay
    switch_scene "🔄 Replay"
    notify "Switched to 🔄 Replay scene"
    ;;
  brb)
    camera_set_ceiling &
    switch_scene "🚬 brb" &
    notify "🚬 BRB Scene"
    ;;
  motion* | feet* | alt*)
    switch_scene "👣 Alternative Camera"
    ;;
  cat)
    switch_scene "😼 LUCKY CAT"
    ;;
  webcam | cam | camera)
    switch_scene "$DEFAULT_SCENE" &
    filter_disable "Webcam" "Freeze" &
    fix_webcam &
    notify "📹 Webcam scene"
    ;;
  thumbs-up | tu | up)
    soundboard_play "ping" &
    emoji_react "👍"
    ;;
  thumbs-down | td | down)
    soundboard_play "buzzer" &
    emoji_react "👎"
    ;;
  emoji | reaction)
    emoji_react "" || exit 1
    ;;
  "")
    echo "Usage: obs-control COMMAND [--mute]" >&2
    exit 2
    ;;
  *)
    echo "Unknown command: $verb" >&2
    exit 2
    ;;
esac

# Trailing "--mute" (e.g. `obs-control brb --mute`).
case "${1:-}" in
  mute | --mute | m | -m)
    mute_mic
    ;;
esac

wait
