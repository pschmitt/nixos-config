#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reflecting the GNOME Keyring unlock
# status.

# Print a per-collection status line; return 0 if all unlocked, 1 if any
# locked. Replaces the zhj `gnome-keyring::status` helper.
keyring_status() {
  local rc=0 coll name
  for coll in $(busctl -j --user --no-pager get-property \
    org.freedesktop.secrets /org/freedesktop/secrets \
    org.freedesktop.Secret.Service Collections 2>/dev/null | jq -er '.data[]' 2>/dev/null)
  do
    name="${coll##*/}"
    if busctl -j --user --no-pager get-property \
      org.freedesktop.secrets "$coll" \
      org.freedesktop.Secret.Collection Locked 2>/dev/null | jq -e '.data' >/dev/null 2>&1
    then
      echo "$name is locked"
      rc=1
    else
      echo "$name is unlocked"
    fi
  done
  return "$rc"
}

main() {
  set -uo pipefail

  local state=false
  local icon="mdi:key-chain-variant"
  local message=""

  if message=$(keyring_status 2>&1)
  then
    state=true
  else
    icon="mdi:key-chain"
  fi

  jq -n \
    --arg icon "$icon" \
    --argjson state "$state" \
    --arg message "$message" \
    '
      def attrs:
        ({}
          | (if $message != "" then . + {message: $message} else . end)
        );

      attrs as $attrs
      | {
          schedule: "@every 30s",
          sensors: [
            (
              {
                sensor_name: "GNOME Keyring",
                sensor_type: "binary",
                sensor_icon: $icon,
                sensor_device_class: "lock",
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
