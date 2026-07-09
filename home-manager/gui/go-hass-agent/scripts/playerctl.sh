#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor with media player state and metadata via playerctl.

get_mpris_player_json() {
  python3 <<'PY'
import json
import sys

import dbus

PREFIX = "org.mpris.MediaPlayer2."
IGNORE = {PREFIX + "playerctld"}


def unwrap(value):
    if isinstance(value, dbus.String):
        return str(value)
    if isinstance(value, dbus.Boolean):
        return bool(value)
    if isinstance(value, (dbus.Int16, dbus.Int32, dbus.Int64, dbus.UInt16, dbus.UInt32, dbus.UInt64)):
        return int(value)
    if isinstance(value, dbus.Double):
        return float(value)
    if isinstance(value, dbus.Array):
        return [unwrap(v) for v in value]
    if isinstance(value, dbus.Dictionary):
        return {str(k): unwrap(v) for k, v in value.items()}
    if isinstance(value, dbus.ObjectPath):
        return str(value)
    return value


def get_player_payload(bus, service):
    proxy = bus.get_object(service, "/org/mpris/MediaPlayer2")
    props = dbus.Interface(proxy, "org.freedesktop.DBus.Properties")
    status = str(props.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus")).lower()
    metadata = unwrap(props.Get("org.mpris.MediaPlayer2.Player", "Metadata"))
    player = service.removeprefix(PREFIX)
    return {
        "service": service,
        "player": player.split(".", 1)[0],
        "play_state": status,
        "title": metadata.get("xesam:title", ""),
        "album": metadata.get("xesam:album", ""),
        "artist": ", ".join(metadata.get("xesam:artist", [])),
        "art_url": metadata.get("mpris:artUrl", ""),
        "track_url": metadata.get("xesam:url", ""),
    }


try:
    bus = dbus.SessionBus()
    dbus_proxy = dbus.Interface(
        bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"),
        "org.freedesktop.DBus",
    )
    services = [
        name for name in dbus_proxy.ListNames()
        if name.startswith(PREFIX) and name not in IGNORE
    ]
except Exception:
    sys.exit(1)

players = []
for service in services:
    try:
        players.append(get_player_payload(bus, service))
    except Exception:
        continue

if not players:
    sys.exit(1)

playing = [player for player in players if player["play_state"] == "playing"]
selected = playing[0] if playing else players[0]
print(json.dumps(selected))
PY
}

get_bruvtab_playing_json() {
  local bruvtab_json
  bruvtab_json="$(bruvtab tabs --playing -j 2>/dev/null)" || return 1

  jq -cer '
    if length == 0 then
      empty
    else
      .[0] | {
        player: "browser",
        play_state: "playing",
        title: (.title // ""),
        album: "",
        artist: "",
        art_url: "",
        track_url: (.url // "")
      }
    end
  ' <<< "$bruvtab_json"
}

get_active_player() {
  local all_players
  all_players="$(playerctl --list-all 2>/dev/null)" || return 1

  # Prefer local players: first playing one, then any
  local player
  player="$(
    playerctl --list-all 2>/dev/null | while IFS= read -r p; do
      local s
      s="$(playerctl --player "$p" status 2>/dev/null)" || continue
      if [[ "$s" == "Playing" ]]; then
        echo "$p"
        return 0
      fi
    done
  )"

  if [[ -n "$player" ]]; then
    echo "$player"
    return 0
  fi

  # Fall back to first available player
  head -1 <<< "$all_players"
}

extract_youtube_id() {
  local url="$1"

  if [[ "$url" =~ (youtube\.com/(watch\?v=|embed/|shorts/)|youtu\.be/)([A-Za-z0-9_-]{11}) ]]
  then
    echo "${BASH_REMATCH[3]}"
    return 0
  fi

  return 1
}

get_youtube_thumbnail() {
  local video_id="$1"
  local cache_file="${XDG_CACHE_HOME:-${HOME}/.cache}/go-hass-agent/youtube-thumb.cache"
  local cached_id="" cached_thumb=""

  if [[ -r "$cache_file" ]]
  then
    read -r cached_id cached_thumb < "$cache_file"
  fi

  if [[ "$video_id" == "$cached_id" && -n "$cached_thumb" ]]
  then
    echo "$cached_thumb"
    return 0
  fi

  local thumb
  thumb="$(timeout 5 yt-dlp --get-thumbnail "https://www.youtube.com/watch?v=${video_id}" 2>/dev/null)" \
    || return 1

  if [[ -z "$thumb" ]]
  then
    return 1
  fi

  mkdir -p "$(dirname "$cache_file")"
  printf '%s %s\n' "$video_id" "$thumb" > "$cache_file"
  echo "$thumb"
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:music-off"

  local player
  player="$(get_active_player 2>/dev/null)" || true

  local playername="" play_state="unavailable" title="" album="" artist="" art_url="" track_url=""

  if [[ -n "${player:-}" ]]; then
    playername="$(awk -F. '{print $1; exit}' <<< "$player")"

    play_state="$(playerctl --player "$player" status 2>/dev/null | tr '[:upper:]' '[:lower:]')" \
      || play_state="unavailable"

    title="$(playerctl --player "$player" metadata title 2>/dev/null || true)"
    album="$(playerctl --player "$player" metadata album 2>/dev/null || true)"
    artist="$(playerctl --player "$player" metadata artist 2>/dev/null || true)"
    art_url="$(playerctl --player "$player" metadata mpris:artUrl 2>/dev/null || true)"
    track_url="$(playerctl --player "$player" metadata xesam:url 2>/dev/null || true)"
  else
    local fallback_json=""
    fallback_json="$(get_bruvtab_playing_json 2>/dev/null)" || true
    if [[ -z "$fallback_json" ]]; then
      fallback_json="$(get_mpris_player_json 2>/dev/null)" || true
    fi
    if [[ -n "$fallback_json" ]]; then
      playername="$(jq -r '.player // empty' <<< "$fallback_json")"
      play_state="$(jq -r '.play_state // "unavailable"' <<< "$fallback_json")"
      title="$(jq -r '.title // empty' <<< "$fallback_json")"
      album="$(jq -r '.album // empty' <<< "$fallback_json")"
      artist="$(jq -r '.artist // empty' <<< "$fallback_json")"
      art_url="$(jq -r '.art_url // empty' <<< "$fallback_json")"
      track_url="$(jq -r '.track_url // empty' <<< "$fallback_json")"
    fi
  fi

  if [[ -z "${playername:-}" ]]; then
    jq -n \
      --argjson state "$state" \
      --arg icon "$icon" \
      '{
        schedule: "@every 10s",
        sensors: [
          {
            sensor_name: "Media Player",
            sensor_type: "binary",
            sensor_icon: $icon,
            sensor_state: $state
          }
        ]
      }'
    return
  fi

  if [[ -z "${art_url:-}" && -n "${track_url:-}" ]]
  then
    local youtube_id
    if youtube_id="$(extract_youtube_id "$track_url")"
    then
      art_url="$(get_youtube_thumbnail "$youtube_id")" || art_url=""
    fi
  fi

  if [[ "$play_state" == "playing" ]]; then
    state=true
    icon="mdi:music"
  else
    icon="mdi:music-note-off"
  fi

  local art_url_attr="N/A"
  if [[ "${art_url:-}" =~ ^https?:// ]]; then
    art_url_attr="$art_url"
  elif [[ "${art_url:-}" =~ ^file:// ]]; then
    local art_file="${art_url#file://}"
    if [[ -r "$art_file" ]]; then
      local mime ext
      mime="$(file --brief --mime-type "$art_file" 2>/dev/null || true)"
      case "$mime" in
        image/png)  ext="png" ;;
        image/jpeg) ext="jpg" ;;
        image/webp) ext="webp" ;;
        *)          ext="png" ;;
      esac
      local remote_name="${HOSTNAME:-$(hostname)}.${ext}"
      local cache_file="${XDG_CACHE_HOME:-${HOME}/.cache}/go-hass-agent/playerctl-art.path"
      local cached_src
      cached_src="$(cat "$cache_file" 2>/dev/null || true)"
      if [[ "$art_file" != "$cached_src" ]]; then
        mkdir -p "$(dirname "$cache_file")"
        ssh -o BatchMode=yes hv "mkdir -p /config/www/playerctl" 2>/dev/null \
          && scp -q "$art_file" "hv:/config/www/playerctl/${remote_name}" 2>/dev/null \
          && echo "$art_file" > "$cache_file"
      fi
      art_url_attr="/local/playerctl/${remote_name}"
    fi
  fi

  jq -n \
    --argjson state "$state" \
    --arg icon "$icon" \
    --arg play_state "$play_state" \
    --arg player "$playername" \
    --arg title "${title:-N/A}" \
    --arg album "${album:-N/A}" \
    --arg artist "${artist:-N/A}" \
    --arg art_url "$art_url_attr" \
    '{
      schedule: "@every 10s",
      sensors: [
        {
          sensor_name: "Media Player",
          sensor_type: "binary",
          sensor_icon: $icon,
          sensor_state: $state,
          sensor_attributes: {
            state: $play_state,
            player: $player,
            title: $title,
            album: $album,
            artist: $artist,
            art_url: $art_url
          }
        }
      ]
    }'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
