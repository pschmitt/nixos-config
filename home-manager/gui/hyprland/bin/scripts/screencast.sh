#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") on|off|status"
}

# Dismiss existing mako notifications from this app (was notification::dismiss).
notification_dismiss() {
  local app_name="$1" id
  for id in $(makoctl list 2>/dev/null \
    | jq -er --arg n "$app_name" '.data[0][] | select(.["app-name"].data == $n).id.data' 2>/dev/null)
  do
    makoctl dismiss -n "$id" 2>/dev/null || true
  done
}

# Links touching a PipeWire node (by node.name regex). Was pw::list-links.
pw_list_links() {
  local node="$1" data
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
        else . end ]')"

  local node_ids
  node_ids="$(jq -er --arg node "$node" '[.[] |
    select(.type == "PipeWire:Interface:Node" and (.info.props["node.name"] | test($node))).id]' <<< "$data")"
  [[ -z "$node_ids" || "$node_ids" == "[]" ]] && return 2

  jq -er --argjson node_ids "$node_ids" '[.[] |
    select(.type == "PipeWire:Interface:Link"
      and ((.info.props["link.input.node"] | inside($node_ids[]))
        or (.info.props["link.output.node"] | inside($node_ids[]))))]' <<< "$data"
}

notify-send-unique() {
  local app_id
  app_id="$(basename "$0")"
  notification_dismiss "$app_id"
  notify-send --app-name="$app_id" \
    --hint "string:x-canonical-private-synchronous:${app_id}" \
    "$@"
}

log() {
  local tag
  tag="$(basename "$0")"
  [[ "$tag" == "bash" ]] && tag="screencast.sh"

  logger --tag "$tag" -- "$* - OUTPUT: $(get_output)"
}

store_state() {
  local state="$1"
  local output="${2:-$(get_output)}"
  local apps="${3:-$(get_screencasting_apps)}"

  if [[ "$state" == "off" ]] || [[ -z "$apps" ]]
  then
    apps="null"
  fi

  log "Storing state: $state (output: $output - apps: $apps)"

  jq -n --arg state "$state" \
    --arg output "$output" \
    --arg ts "$(date '+%s')" \
    --argjson apps "$apps" \
    '{"state": $state, "output": $output, "timestamp": $ts, "apps": $apps}' \
    > "$STATEFILE"
}

screencast_running() {
  jq -e '.state == "on"' "$STATEFILE" &>/dev/null
}

get_output() {
  jq -er '.output' "$STATEFILE" 2>/dev/null
}

get_screencasting_apps() {
  # NOTE The exact name of the portal is
  # ".xdg-desktop-portal-hyprland-wrapped"
  local portal="xdg-desktop-portal"

  pw_list_links "$portal" | \
    jq -cer '[
      .[].input_node_info.info.props["node.name"]
    ] | unique' 2>/dev/null

  # Get data from cache
  # jq -er '.app' "$STATEFILE" 2>/dev/null
}

has_screencasting_apps() {
  get_screencasting_apps | jq -er 'length > 0' &>/dev/null
}

state_is_recent() {
  local now ts

  now="$(date '+%s')"
  ts="$(jq -er '.timestamp // 0' "$STATEFILE" 2>/dev/null)"

  # Check if the state is less than 10 seconds old
  (( now - ts < 30 ))
}

screencast_status() {
  if ! screencast_running
  then
    echo "Screencasting is off"
    return 1
  fi

  local output apps
  output="$(get_output)"
  apps="$(get_screencasting_apps | jq -er '.[]')"

  local apps_single_line
  apps_single_line="$(tr '\n' ' ' <<<"$apps")"
  echo "Screencasting is on (Output: ${output:-N/A} - Apps: ${apps_single_line%% })"
  return 0
}

screencast_on() {
  # Store state
  store_state "on"

  notify-send-unique "📹 Screencast started"
  log "Screencast started"

  # Pause notifications
  # makoctl mode -a do-not-disturb

  # Update waybar module (signal: 7)
  pkill -RTMIN+7 waybar
}

screencast_off() {
  if has_screencasting_apps
  then
    log "Screencast not stopped because there are still screencasting apps"
    store_state "on"
    return 1
  fi

  if ! screencast_running || ! state_is_recent
  then
    log "Screencast already off or state is stale"
    store_state "off"
    return 0
  fi
  # Store state
  store_state "off"

  # Resume notifications
  # makoctl mode -r do-not-disturb

  notify-send-unique "❌ Screencast stopped"
  log "Screencast stopped"

  # Update waybar module (signal: 7)
  pkill -RTMIN+7 waybar
}

select_output() {
  local output

  output="$(get_output)"

  if ! state_is_recent
  then
    log "*Not* reusing output '$output' because it's too old"
  fi

  if [[ -n "$output" ]] && state_is_recent
  then
    log "📹 Selected PREVIOUS output $output"
    # Store state again here because here it will probably be "off"
    # browsers only grab the screen once to display a preview screenshot
    store_state "on" "$output"

    echo "$output"
    return 0
  fi

  if ! output=$(slurp -f %o -or)
  then
    store_state "off"
    return 1
  fi

  log "📹 Selected output $output"

  # FIXME This might return the floating display selection window, instead of
  # the main application window (Firefox, Chrome etc.)
  app="$(hyprctl -j activewindow)"

  store_state "on" "$output" "$app"

  echo "$output"
  return 0
}

STATEFILE="${TMPDIR:-/tmp}/screencast.json"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  log "Called with $*"

  case "$1" in
    help|h|-h|--help)
      usage
      exit 0
      ;;
    status|state)
      shift
      screencast_status "$@"
      ;;
    on|enable|1|start*)
      shift
      screencast_on "$@"
      ;;
    off|disable|0|stop*)
      shift
      screencast_off "$@"
      ;;
    *sel*)
      shift
      select_output "$@"
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
fi
