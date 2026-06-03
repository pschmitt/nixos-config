#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor with media player state and metadata via playerctl.

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

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:music-off"

  local player
  player="$(get_active_player 2>/dev/null)" || true

  if [[ -z "${player:-}" ]]; then
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

  local playername
  playername="$(awk -F. '{print $1; exit}' <<< "$player")"

  local play_state
  play_state="$(playerctl --player "$player" status 2>/dev/null | tr '[:upper:]' '[:lower:]')" \
    || play_state="unavailable"

  local title album artist art_url
  title="$(playerctl --player "$player" metadata title 2>/dev/null || true)"
  album="$(playerctl --player "$player" metadata album 2>/dev/null || true)"
  artist="$(playerctl --player "$player" metadata artist 2>/dev/null || true)"
  art_url="$(playerctl --player "$player" metadata mpris:artUrl 2>/dev/null || true)"

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
