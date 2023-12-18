#!/usr/bin/env bash

add_to_path() {
  local dir="$1"

  if ! grep -q "$dir" <<< "$PATH"
  then
    export PATH="${PATH}:${dir}"
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

  zhj -x "bt::setup-headset --notify '$mac_addr'"
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

  notify-send -c bluetooth "󰂲 Bluetooth headset disconnected" "$name"
}

event_type() {
  local type
  type="$(jq -er '.type' <<< "$data")"
  if [[ "$type" != "signal" ]]
  then
    echo "Ignored event type: $type" >&2
    return 1
  fi

  local member
  member="$(jq -er '.member' <<< "$data")"
  if [[ "$member" != "PropertiesChanged" ]]
  then
    echo "Ignored member: $member" >&2
    return 1
  fi

  local payload endpoint
  payload="$(jq -er '.payload.data | to_entries' <<< "$data")"
  endpoint="$(jq -er '.[0].value' <<< "$payload")"
  if [[ "$endpoint" != "org.bluez.Device1" ]]
  then
    echo "Ignored endpoint: $endpoint" >&2
    return 1
  fi

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

  sudo busctl monitor org.bluez --json=short \
    --match="type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',arg0='org.bluez.Device1'" |
  while IFS= read -r LINE
  do
    process_msg "$LINE"
  done
fi

# vim: set ft=bash et ts=2 sw=2 :
