#!/usr/bin/env bash

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
  local payload
  payload="$(jq -er '.payload.data | to_entries' <<< "$data")"

  local property
  property="$(jq -er '.[1].value | keys[0]' <<< "$payload")"
  if [[ "$property" != "Connected" ]]
  then
    echo "Ignored property: $property" >&2
    return 1
  fi

  if <<<"$payload" jq -er '.[1].value.Connected.data' >/dev/null
  then
    echo "connected"
    return 0
  else
    echo "disconnected"
    return 0
  fi
}

process_msg() {
  local data="$1"

  # if [[ -n "$DEBUG" ]]
  # then
  #   echo "DEBUG: $line" >&2
  #   jq . <<< "$line"
  # fi

  event_type="$(event_type "$data")"

  (
    case "$event_type" in
      connected)
        bt_connected "$data"
        ;;
      disconnected)
        bt_disconnected "$data"
        ;;
      *)
        # [[ -n "$DEBUG" ]] && echo "Unknown event type: $event_type" 2>&1
        return 1
        ;;
    esac
  ) &
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  # Add $HOME/bin to PATH (for zhj)
  add_to_path "${HOME}/bin"
  # Add /run/wrappers/bin to PATH (for sudo)
  add_to_path "/run/wrappers/bin"

  DBUS_FILTER_TYPE="signal"
  DBUS_FILTER_INTERFACE="org.freedesktop.DBus.Properties"
  DBUS_FILTER_MEMBER="PropertiesChanged"
  DBUS_FILTER_ARG0="org.bluez.Device1"

  DBUS_FILTER="type='${DBUS_FILTER_TYPE}',\
    interface='${DBUS_FILTER_INTERFACE}',\
    member='${DBUS_FILTER_MEMBER}',\
    arg0='${DBUS_FILTER_ARG0}'"

  sudo busctl monitor --system --json=short --match="$DBUS_FILTER" |
  while IFS= read -r LINE
  do
    process_msg "$LINE"
  done
fi

# vim: set ft=bash et ts=2 sw=2 :
