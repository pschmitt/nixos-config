#!/usr/bin/env bash

# DEBUG
# set -x

udev-export-device-info() {
  local devpath="$1"
  local info
  info="$(udevadm info --no-pager --export --path="$devpath" | \
    awk -F ': ' '/=.+/ {
      if ($2 ~ /^.*=".*"$/) {
          print "export " $2
      } else {
          gsub(/=/, "=\"", $2);
          print "export " $2 "\""
      }
    }' | \
    grep -vE '^export (PATH=|[0-9]+)')"

  eval "$info"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  TARGET_USER="${TARGET_USER:-pschmitt}"

  # Restart the script as the target user if necessary
  if [[ ${USER:-$(id -n -u)} != "$TARGET_USER" ]]
  then
    echo "Re-executing as $TARGET_USER" >&2
    exec su "$TARGET_USER" -c \
      "exec systemd-cat --identifier=udev-custom-callback $0 $*"
  fi

  UDEV_ACTION="$1"
  UDEV_DEVICE_PATH="$2"
  # FIXME Below only works for connected devices (ie it won't work when
  # UDEV_ACTION is "remove")
  udev-export-device-info "$UDEV_DEVICE_PATH"

  case "$ID_BUS" in
    bluetooth)
      case "$UDEV_ACTION" in
        add)
          zhj "bt::setup-headset-udev --notify '$NAME'"
          exit 0
          ;;
        remove)
          zhj "bt::disconnect-headset-udev --notify '$NAME'"
          exit 0
          ;;
        *)
          echo "Unknown action: $UDEV_ACTION" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Unknown ID_BUS value: $ID_BUS" >&2
      exit 1
      ;;
  esac
fi

# vim: set ft=bash et ts=2 sw=2 :
