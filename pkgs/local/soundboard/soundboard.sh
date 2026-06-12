# soundboard — Nix-native replacement for the zhj-backed soundboard:: zsh
# helpers. Plays local sound files into the (declaratively-created)
# "soundboard-sink" PipeWire null-sink and links that sink's monitor into the
# same apps the default microphone feeds (so OBS/Teams capture it) plus the
# default sink (so it is audible locally).
#
# Scope vs the zsh original: local playback + routing only. The --tts,
# kitchen (Home Assistant), --remote (scp) and download (yt-dlp) paths are
# intentionally not ported.

shopt -s nullglob

SOUNDBOARD_DIR="${SOUNDBOARD_DIR:-${HOME}/Music/Soundboard}"
SOUNDBOARD_SINK="${SOUNDBOARD_SINK:-soundboard-sink}"
SOUNDBOARD_VOLUME="${SOUNDBOARD_VOLUME:-70}" # percent

default_sink() {
  pactl get-default-sink
}

default_source() {
  pactl get-default-source
}

# ── PipeWire graph helpers (ported from pw::*) ─────────────────────────────
# All links touching a node (by node.name regex), as a JSON array.
pw_list_links() {
  local node="$1"

  local data
  data="$(pw-dump | jq -er '
    (map(select(.type == "PipeWire:Interface:Node")) | reduce .[] as $item ({}; .[$item.id | tostring] = $item)) as $nodes
    | (map(select(.type == "PipeWire:Interface:Port")) | reduce .[] as $item ({}; .[$item.id | tostring] = $item)) as $ports
    | [ .[]
      | if .type == "PipeWire:Interface:Link" then
          . + {
            output_node_info: $nodes[(.info["output-node-id"] | tostring)],
            input_node_info: $nodes[(.info["input-node-id"] | tostring)],
            output_port_info: $ports[(.info["output-port-id"] | tostring)],
            input_port_info: $ports[(.info["input-port-id"] | tostring)]
          }
        else
          .
        end
      ]
  ')"

  local node_ids
  node_ids="$(jq -er --arg node "$node" '[.[] |
    select(.type == "PipeWire:Interface:Node" and (.info.props["node.name"] | test($node))).id]' <<< "$data")"

  if [[ -z "$node_ids" || "$node_ids" == "[]" ]]
  then
    echo "Failed to determine node id for $node" >&2
    return 2
  fi

  jq -er --argjson node_ids "$node_ids" '[.[] |
    select(
      .type == "PipeWire:Interface:Link"
      and (
        (.info.props["link.input.node"] | inside($node_ids[]))
        or
        (.info.props["link.output.node"] | inside($node_ids[]))
      )
    )]' <<< "$data"
}

# Output (or input) port names of a node, one per line.
pw_ports() {
  local dir="$1" device="$2" # dir: --output | --input
  pw-link "$dir" | sort | grep -Ei -- "$device" || true
}

# Link every output port of SOURCE to the input ports of TARGET, matching the
# channel layout (mono/stereo) the way pw::link did.
pw_link() {
  local source="$1" target="$2"
  local -a src_ports tgt_ports

  mapfile -t src_ports < <(pw_ports --output "$source")
  mapfile -t tgt_ports < <(pw_ports --input "$target")

  if [[ "${#src_ports[@]}" -eq 0 || "${#tgt_ports[@]}" -eq 0 ]]
  then
    return 1
  fi

  if [[ "${#src_ports[@]}" -eq 1 ]]
  then
    local p
    for p in "${tgt_ports[@]}"
    do
      pw-link "${src_ports[0]}" "$p" 2>/dev/null || true
    done
  elif [[ "${#src_ports[@]}" -eq 2 ]]
  then
    case "${#tgt_ports[@]}" in
      1)
        pw-link "${src_ports[0]}" "${tgt_ports[0]}" 2>/dev/null || true
        pw-link "${src_ports[1]}" "${tgt_ports[0]}" 2>/dev/null || true
        ;;
      2)
        pw-link "${src_ports[0]}" "${tgt_ports[0]}" 2>/dev/null || true
        pw-link "${src_ports[1]}" "${tgt_ports[1]}" 2>/dev/null || true
        ;;
      *)
        echo "Unsupported target port count (${#tgt_ports[@]})" >&2
        return 3
        ;;
    esac
  else
    echo "Unsupported source port count (${#src_ports[@]})" >&2
    return 3
  fi
}

# Destroy every link touching NODE.
pw_unlink() {
  local node="$1" link
  for link in $(pw_list_links "$node" 2>/dev/null | jq -er '.[].id' 2>/dev/null)
  do
    pw-cli destroy "$link" 2>/dev/null || true
  done
}

# Link $1 (sink) to the same app inputs the default source currently feeds.
link_same_as_default_source() {
  local to="$1" ignore="${2:-}"
  local from
  from="$(default_source)"

  local -a targets
  mapfile -t targets < <(
    pw_list_links "$from" 2>/dev/null \
      | jq -er '.[].input_port_info.info.props["port.alias"]' 2>/dev/null \
      | grep -v "PulseAudio Volume Control" \
      | sed -E 's#:[^:]*$##' \
      | sort -u
  )

  local t
  for t in "${targets[@]}"
  do
    [[ -z "$t" ]] && continue
    [[ -n "$ignore" && "$t" == "$ignore" ]] && continue
    pw_link "$to" "$t" || true
  done
}

connect() {
  pw_unlink "$SOUNDBOARD_SINK"
  # Feed the same apps the mic feeds (so OBS/Teams capture it), ignoring cava.
  link_same_as_default_source "$SOUNDBOARD_SINK" "cava"
  # Feedback so we hear the effect locally.
  local ds
  ds="$(default_sink)"
  [[ -n "$ds" ]] && pw_link "$SOUNDBOARD_SINK" "$ds" || true
}

# ── Routing reset (ported from pulseaudio::*) ───────────────────────────────
mute_monitor_sources() {
  local src
  while IFS= read -r src
  do
    [[ -n "$src" ]] && pactl set-source-mute "$src" 1 2>/dev/null || true
  done < <(pactl list short sources | awk -F'\t' '$2 ~ /\.monitor/ && $2 !~ /soundboard/ { print $2 }')
}

set_default_source_for_all_apps() {
  local source index
  source="$(default_source)"
  while IFS= read -r index
  do
    [[ -n "$index" ]] && pactl move-source-output "$index" "$source" 2>/dev/null || true
  done < <(pactl -f json list source-outputs | jq -er '
    .[] | select(.properties["application.id"] != "org.PulseAudio.pavucontrol") | .index')
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

  # Awkward-but-faithful routing settle: re-pin app mic inputs and mute
  # monitor sources to avoid feedback while the effect plays.
  (
    mute_monitor_sources
    set_default_source_for_all_apps
    sleep 1
    sleep 2
    set_default_source_for_all_apps
  ) &

  volume="$(awk -v v="$SOUNDBOARD_VOLUME" 'BEGIN { print v / 100.0 }')"
  pw-play --target "$SOUNDBOARD_SINK" --volume "$volume" "$file"
  wait
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
