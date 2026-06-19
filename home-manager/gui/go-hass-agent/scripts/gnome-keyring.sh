#!/usr/bin/env bash
# Emits a Go Hass Agent binary sensor reflecting the GNOME Keyring unlock
# status.

# busctl cannot hold a Secret Service session open across separate invocations
# (each call is a fresh D-Bus connection), and gnome-keyring-daemon requires an
# active session before it will answer Locked property reads.  A single Python
# process keeps one connection open, calls OpenSession once, then reads all
# collection states.
#
# Old approach (busctl — crashes without an active session):
# keyring_status() {
#   local rc=0 coll name
#   for coll in $(busctl -j --user --no-pager get-property \
#     org.freedesktop.secrets /org/freedesktop/secrets \
#     org.freedesktop.Secret.Service Collections 2>/dev/null | jq -er '.data[]' 2>/dev/null)
#   do
#     name="${coll##*/}"
#     if busctl -j --user --no-pager get-property \
#       org.freedesktop.secrets "$coll" \
#       org.freedesktop.Secret.Collection Locked 2>/dev/null | jq -e '.data' >/dev/null 2>&1
#     then
#       echo "$name is locked"
#       rc=1
#     else
#       echo "$name is unlocked"
#     fi
#   done
#   return "$rc"
# }
keyring_status() {
  python3 - <<'PYEOF'
import dbus
import sys

bus = dbus.SessionBus()
svc_obj = bus.get_object('org.freedesktop.secrets', '/org/freedesktop/secrets')
service = dbus.Interface(svc_obj, 'org.freedesktop.Secret.Service')
service.OpenSession('plain', dbus.String('', variant_level=1))

props = dbus.Interface(svc_obj, 'org.freedesktop.DBus.Properties')
colls = props.Get('org.freedesktop.Secret.Service', 'Collections')

rc = 0
for path in colls:
    name = str(path).split('/')[-1]
    obj = bus.get_object('org.freedesktop.secrets', str(path))
    coll_props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
    locked = bool(coll_props.Get('org.freedesktop.Secret.Collection', 'Locked'))
    print(f"{name} is {'locked' if locked else 'unlocked'}")
    if locked:
        rc = 1

sys.exit(rc)
PYEOF
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

# vim: set ft=sh et ts=2 sw=2 :
