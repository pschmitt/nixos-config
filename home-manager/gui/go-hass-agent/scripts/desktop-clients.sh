#!/usr/bin/env bash
# Emits desktop client counts with focused window details as a Go Hass Agent sensor.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

CLIENTS_JSON="[]"
FOCUSED_CLIENT="null"
ERROR_MSG=""

collect_sway_clients() {
  local tree result focused

  if ! tree=$(swaymsg_wrapper -t get_tree)
  then
    ERROR_MSG="Failed to query sway tree"
    return 1
  fi

  if ! result=$(jq -c '
      def walk:
        recurse(.nodes[]?, .floating_nodes[]?);

      [walk | select(.type == "con" and (.pid // 0) > 0) | {
          class: (.app_id // .window_properties.class // "unknown"),
          title: (.name // .window_properties.title // ""),
          pid: (.pid // 0),
          focused: (.focused // false)
        }]
      as $clients
      | {
          clients: $clients,
          focused: ($clients | map(select(.focused == true)) | first // null)
        }
    ' <<<"$tree")
  then
    ERROR_MSG="Failed to parse sway tree"
    return 1
  fi

  if ! CLIENTS_JSON=$(jq -cr '.clients' <<<"$result")
  then
    CLIENTS_JSON="[]"
  fi

  if ! focused=$(jq -c '.focused' <<<"$result")
  then
    focused="null"
  fi
  if [[ -z "$focused" || "$focused" == "null" ]]
  then
    FOCUSED_CLIENT="null"
  else
    FOCUSED_CLIENT="$focused"
  fi

  return 0
}

collect_hyprland_clients() {
  local clients_json="" focused_json="" active_raw="" focus_addr=""

  if ! clients_json=$(hyprctl_wrapper -j clients)
  then
    ERROR_MSG="Failed to query Hyprland clients"
    return 1
  fi

  if ! active_raw=$(hyprctl_wrapper -j activewindow)
  then
    ERROR_MSG="Failed to query Hyprland active window"
    active_raw="null"
  fi

  if ! focus_addr=$(jq -r '.address // empty' <<<"$active_raw")
  then
    focus_addr=""
  fi

  if ! CLIENTS_JSON=$(jq -c --arg focus "$focus_addr" '
        map({
          class: (.class // ""),
          title: (.title // ""),
          pid: (.pid // 0),
          workspace: (.workspace.name // .workspace // ""),
          monitor: (.monitor // ""),
          address: (.address // ""),
          focused: (.address == $focus and $focus != "")
        })
      ' <<<"$clients_json")
  then
    CLIENTS_JSON="[]"
  fi

  if ! focused_json=$(jq -c '{
        class: (.class // ""),
        title: (.title // ""),
        pid: (.pid // 0),
        workspace: (.workspace.name // .workspace // ""),
        monitor: (.monitor // ""),
        address: (.address // "")
      }' <<<"$active_raw")
  then
    focused_json="null"
  fi

  if [[ -z "$focused_json" || "$focused_json" == "null" ]]
  then
    FOCUSED_CLIENT="null"
  else
    FOCUSED_CLIENT="$focused_json"
  fi

  return 0
}

main() {
  set -uo pipefail

  local desktop=""
  local session=""
  local state_count="0"
  local state_value=0
  local icon="mdi:application-array"

  # shellcheck disable=SC2119
  if ! desktop=$(guess_desktop)
  then
    desktop=""
  fi

  if ! session=$(guess_session_type)
  then
    session=""
  fi

  if [[ -n "$desktop" ]]
  then
    case "$desktop" in
      sway)
        collect_sway_clients
        ;;
      Hyprland)
        collect_hyprland_clients
        ;;
      *)
        ERROR_MSG="Unsupported desktop: ${desktop}"
        ;;
    esac
  else
    ERROR_MSG="No desktop detected"
  fi

  if ! state_count=$(jq -r 'length' <<<"$CLIENTS_JSON")
  then
    state_count=0
  fi

  if [[ "$state_count" =~ ^[0-9]+$ ]]
  then
    state_value="$state_count"
  else
    state_value=0
  fi

  if (( state_value == 0 ))
  then
    icon="mdi:application-off"
  elif (( state_value == 1 ))
  then
    icon="mdi:application"
  fi

  local focused_json="null"
  if [[ -n "$FOCUSED_CLIENT" && "$FOCUSED_CLIENT" != "null" ]]
  then
    focused_json="$FOCUSED_CLIENT"
  fi

  jq -n \
    --arg icon "$icon" \
    --arg desktop "$desktop" \
    --arg session "$session" \
    --arg error "$ERROR_MSG" \
    --argjson focused "$focused_json" \
    --argjson clients "$CLIENTS_JSON" \
    --argjson state "$state_value" \
    '
      def attrs:
        ({ }
          | (if $focused != null then . + {focused_client: $focused} else . end)
          | (if $clients != [] then . + {clients: $clients} else . end)
          | (if $desktop != "" then . + {desktop: $desktop} else . end)
          | (if $session != "" then . + {session_type: $session} else . end)
          | (if $error != "" then . + {error: $error} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 5s",
          sensors: [
            (
              {
                sensor_name: "Desktop Clients",
                sensor_icon: $icon,
                sensor_state: $state
              }
              + (if ($attrs | length) > 0 then { sensor_attributes: $attrs } else {} end)
            )
          ]
        }
    '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
