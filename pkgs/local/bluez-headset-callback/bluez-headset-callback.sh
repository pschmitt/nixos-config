#!/usr/bin/env bash

# Seconds to wait for a device to settle before acting on a Connected change.
# Flapping devices (eg. a Jabra sitting in its case nearby) emit connect +
# disconnect bursts microseconds apart, so we never trust a single event.
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-3}"

# Per-device state lives here. XDG_RUNTIME_DIR is a per-user tmpfs that is
# wiped on logout, so state never goes stale across sessions.
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/bluez-headset-callback"

add_to_path() {
  local dir="$1"

  if ! grep -q "$dir" <<< "$PATH"
  then
    export PATH="${dir}:${PATH}"
  fi
}

extract_mac_addr() {
  jq -er '.path' | sed 's#_#:#g' | \
    zhj grep-mac-address -o --color=never
}

bt_connected() {
  local data="$1"
  local mac_addr
  mac_addr="$(extract_mac_addr <<< "$data")"

  if [[ -n "$DEBUG" ]]
  then
    jq -er '.' <<< "$data"
  fi

  zhj "bt::setup-headset --notify '$mac_addr'"
}

bt_disconnected() {
  local data="$1"
  local mac_addr name
  mac_addr="$(extract_mac_addr <<< "$data")"
  name="$(zhj bt::mac-address-to-name "$mac_addr")"

  if [[ -n "$DEBUG" ]]
  then
    jq -er '.' <<< "$data"
  fi

  notify-send -c bluetooth "󰂲 Bluetooth device disconnected" "$name"
}

event_type() {
  local data="$1"
  local payload
  payload="$(jq -er '.payload.data | to_entries' <<< "$data")"

  local property
  property="$(jq -er '.[1].value | keys[0]' <<< "$payload")"
  if [[ "$property" != "Connected" ]]
  then
    echo "Ignored property: $property" >&2
    return 1
  fi

  if jq -er '.[1].value.Connected.data' <<< "$payload" >/dev/null
  then
    echo "connected"
    return 0
  else
    echo "disconnected"
    return 0
  fi
}

# Wait for the device to settle, then act on its *actual* state only when it
# differs from the last state we acted on. This collapses flapping devices and
# avoids spurious setup-headset calls / disconnect notifications.
debounce() {
  local mac="$1" ts="$2" data="$3"
  local key="${mac//:/_}"
  local seen_file="${STATE_DIR}/${key}.seen"
  local state_file="${STATE_DIR}/${key}.state"

  # Mark this as the most recent event seen for this device.
  printf '%s\n' "$ts" > "$seen_file"

  sleep "$DEBOUNCE_SECONDS"

  # A newer event arrived for this device while we waited: let it win.
  if [[ "$(cat "$seen_file" 2>/dev/null)" != "$ts" ]]
  then
    return 0
  fi

  # Trust the actual current connection state, not the (flapping) payload.
  local current
  if zhj bt::is-connected "$mac" >/dev/null 2>&1
  then
    current="connected"
  else
    current="disconnected"
  fi

  local previous
  previous="$(cat "$state_file" 2>/dev/null)"
  printf '%s\n' "$current" > "$state_file"

  # Nothing changed since we last acted: stay quiet.
  if [[ "$current" == "$previous" ]]
  then
    return 0
  fi

  # First time we see this device this session and it is not connected: this is
  # just the baseline, not a real disconnect -> stay quiet.
  if [[ -z "$previous" && "$current" == "disconnected" ]]
  then
    return 0
  fi

  case "$current" in
    connected)
      bt_connected "$data"
      ;;
    disconnected)
      bt_disconnected "$data"
      ;;
  esac
}

process_msg() {
  local data="$1"

  # Only react to "Connected" property changes; ignore everything else.
  if ! event_type "$data" >/dev/null
  then
    return 0
  fi

  local mac_addr
  mac_addr="$(extract_mac_addr <<< "$data")"
  if [[ -z "$mac_addr" ]]
  then
    return 0
  fi

  local ts
  ts="$(jq -er '."timestamp-realtime" // empty' <<< "$data")"

  debounce "$mac_addr" "$ts" "$data" &
}

main() {
  # Add $HOME/bin to PATH (for zhj)
  add_to_path "${HOME}/bin"
  # Add /run/wrappers/bin to PATH (for sudo)
  add_to_path "/run/wrappers/bin"

  mkdir -p "$STATE_DIR"

  local dbus_filter_type="signal"
  local dbus_filter_interface="org.freedesktop.DBus.Properties"
  local dbus_filter_member="PropertiesChanged"
  local dbus_filter_arg0="org.bluez.Device1"

  local dbus_filter="type='${dbus_filter_type}',\
    interface='${dbus_filter_interface}',\
    member='${dbus_filter_member}',\
    arg0='${dbus_filter_arg0}'"

  local line
  sudo busctl monitor --system --json=short --match="$dbus_filter" |
  while IFS= read -r line
  do
    process_msg "$line"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=bash et ts=2 sw=2 :
