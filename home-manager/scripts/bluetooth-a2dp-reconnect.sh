# shellcheck shell=bash

# Restore A2DP on Bluetooth headsets after PipeWire/WirePlumber (re)start.
#
# BlueZ keeps a headset connected across an audio stack restart, but the A2DP
# transport goes away with PipeWire's media endpoints and is not reconnected:
# the card comes back with headset (HFP) profiles only. Ask BlueZ to connect
# the A2DP sink profile again and restore the profile WirePlumber had saved.

A2DP_SINK_UUID="0000110b-0000-1000-8000-00805f9b34fb"
CARD_TIMEOUT="${CARD_TIMEOUT:-20}"
SETTLE_SECONDS="${SETTLE_SECONDS:-5}"
WP_PROFILE_STATE="${XDG_STATE_HOME:-${HOME}/.local/state}/wireplumber/default-profile"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-h|--help]

Reconnect the A2DP profile of connected Bluetooth headsets whose PipeWire
card lost it.
EOF
}

# Print "OBJECT_PATH MAC" for every connected device offering an A2DP sink.
connected_a2dp_devices() {
  busctl --system --json=short call org.bluez / \
    org.freedesktop.DBus.ObjectManager GetManagedObjects |
    jq -r --arg uuid "$A2DP_SINK_UUID" '
      .data[0] | to_entries[]
      | (.value["org.bluez.Device1"] // empty) as $dev
      | select($dev.Connected.data and ($dev.UUIDs.data | index($uuid)))
      | "\(.key) \($dev.Address.data)"'
}

card_exists() {
  pactl list cards short | awk '{ print $2 }' | grep -qxF "$1"
}

card_has_a2dp() {
  pactl -f json list cards | jq -e --arg card "$1" '
    any(.[] | select(.name == $card) | .profiles | to_entries[];
      (.key | startswith("a2dp-sink")) and .value.available)' >/dev/null
}

wait_for() {
  local timeout="$1"
  shift
  local i

  for ((i = 0; i < timeout; i++))
  do
    if "$@"
    then
      return 0
    fi
    sleep 1
  done
  return 1
}

saved_profile() {
  [[ -r "$WP_PROFILE_STATE" ]] || return 1
  sed -n "s/^${1}=//p" "$WP_PROFILE_STATE" | tail -1
}

reconnect_device() {
  local path="$1" mac="$2"
  local card="bluez_card.${mac//:/_}"
  local profile

  if ! wait_for "$CARD_TIMEOUT" card_exists "$card"
  then
    echo "$mac: no PipeWire card $card, reconnecting A2DP anyway" >&2
  elif wait_for "$SETTLE_SECONDS" card_has_a2dp "$card"
  then
    echo "$mac: A2DP available"
    return 0
  fi

  echo "$mac: A2DP missing, reconnecting the A2DP sink profile"
  if ! busctl --system call org.bluez "$path" org.bluez.Device1 \
    ConnectProfile s "$A2DP_SINK_UUID"
  then
    echo "$mac: ConnectProfile failed" >&2
    return 1
  fi

  if ! wait_for 10 card_has_a2dp "$card"
  then
    echo "$mac: A2DP still unavailable on $card" >&2
    return 1
  fi

  # WirePlumber does not switch back by itself once A2DP reappears.
  profile="$(saved_profile "$card")"
  if [[ "$profile" == a2dp-sink* ]]
  then
    echo "$mac: restoring saved profile $profile"
    pactl set-card-profile "$card" "$profile"
  fi
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  local path mac rc=0
  while read -r path mac
  do
    [[ -n "$path" ]] || continue
    reconnect_device "$path" "$mac" || rc=1
  done < <(connected_a2dp_devices)
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
  exit $?
fi

# vim: set ft=sh et ts=2 sw=2 :
