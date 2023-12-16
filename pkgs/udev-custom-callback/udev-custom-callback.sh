#!/usr/bin/env bash

# set -x

udev-export-device-info() {
  local devpath="$1"
  local info
  info="$(udevadm info --no-pager --export -p "$devpath" | \
    awk -F '.: ' '/=/ && !/PATH=/ { print "export " $2 }')"

  eval "$info"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  TARGET_USER="pschmitt"

  # Restart the script as the target user if necessary
  if [[ ${USER:-(id -n -u)} != "$TARGET_USER" ]]
  then
    echo "Re-executing as $TARGET_USER" >&2
    exec su "$TARGET_USER" -c \
      "systemd-cat --identifier=udev-custom-callback $0 $*"
  fi

  UDEV_DEVICE_PATH="$1"
  udev-export-device-info "$UDEV_DEVICE_PATH"

  case "$ID_BUS" in
    bluetooth)
      zhj "bt::setup-headset --notify '$NAME'"
      ;;
    *)
      echo "Unknown ID_BUS value: $ID_BUS" >&2
      exit 2
      ;;
  esac
fi

# vim: set ft=bash et ts=2 sw=2 :
