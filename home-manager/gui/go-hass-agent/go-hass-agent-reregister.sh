#!/usr/bin/env bash
# Delete the mobile_app device from Home Assistant and re-register
# go-hass-agent. Wrapped by the go-hass-agent home-manager module as
# go-hass-agent-reregister.
set -euo pipefail

usage() {
  echo "Usage: ${0##*/} [DEVICE_NAME]"
  echo
  echo "DEVICE_NAME defaults to \$HOSTNAME if omitted."
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

DEVICE_NAME="${1:-$HOSTNAME}"
DEBUG="${DEBUG:-0}"
ENV_FILE="${GO_HASS_AGENT_ENV_FILE:-/run/secrets/rendered/go-hass-agent.env}"
PREFS="${XDG_CONFIG_HOME:-$HOME/.config}/go-hass-agent/preferences.toml"

if [[ -z "$DEVICE_NAME" ]]
then
  usage
  exit 2
fi

if [[ -f "$ENV_FILE" ]]
then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

HASS_SERVER="${HASS_SERVER:-}"
HASS_TOKEN="${HASS_TOKEN:-}"

if [[ -z "$HASS_SERVER" || -z "$HASS_TOKEN" ]] && [[ -f "$PREFS" ]]
then
  read -r HASS_SERVER HASS_TOKEN <<<"$(tomlq -r '
    .registration | "\(.server) \(.token)"
  ' "$PREFS")"
fi

if [[ -z "$HASS_SERVER" || -z "$HASS_TOKEN" ]]
then
  echo "Error: Server or token is missing (env + preferences)" >&2
  exit 1
fi

for dep in curl go-hass-agent jq websocat
do
  if ! command -v "$dep" >/dev/null
  then
    echo "$dep not found in PATH" >&2
    exit 2
  fi
done

if [[ "$HASS_SERVER" == https://* || "$HASS_SERVER" == http://* ]]
then
  HA_HTTP_BASE="${HASS_SERVER%/}"
else
  HA_HTTP_BASE="http://$HASS_SERVER"
fi

if [[ "$HASS_SERVER" == https://* ]]
then
  HA_WS_URL="wss://${HASS_SERVER#https://}/api/websocket"
elif [[ "$HASS_SERVER" == http://* ]]
then
  HA_WS_URL="ws://${HASS_SERVER#http://}/api/websocket"
else
  HA_WS_URL="ws://${HASS_SERVER}/api/websocket"
fi

get_devices() {
  if [[ "$DEBUG" == "1" ]]
  then
    echo "DEBUG: connecting to $HA_WS_URL for device_registry/list" >&2
  fi

  websocat -B 1048576 -t "$HA_WS_URL" < <(
    printf '%s\n' "{\"type\":\"auth\",\"access_token\":\"$HASS_TOKEN\"}"
    sleep 0.2
    printf '%s\n' '{"id":1,"type":"config/device_registry/list"}'
    sleep 2
  )
}

select_mobile_app_device() {
  local name="$1"

  jq -c --arg name "$name" '
    select(.id == 1 and .type == "result" and .success == true)
    | .result[]
    | select(
        ((.name // "") == $name)
        or
        ((.name_by_user // "") == $name)
      )
    | select(
        (.identifiers // [])
        | map(type == "array" and (.[0] // "") == "mobile_app")
        | any
      )
  '
}

delete_config_entry() {
  local entry_id="$1"
  local url="$HA_HTTP_BASE/api/config/config_entries/entry/$entry_id"

  if [[ "$DEBUG" == "1" ]]
  then
    echo "DEBUG: DELETE $url" >&2
  fi

  local tmp status
  tmp="$(mktemp)"

  status="$(
    curl -sS -o "$tmp" -w '%{http_code}' \
      -X DELETE \
      -H "Authorization: Bearer $HASS_TOKEN" \
      -H "Content-Type: application/json" \
      "$url"
  )"

  if [[ "$DEBUG" == "1" ]]
  then
    echo "DEBUG: HTTP $status, body:" >&2
    cat "$tmp" >&2 || true
  fi

  if [[ "$status" == "200" ]]
  then
    rm -f "$tmp"
    return 0
  fi

  echo "Error deleting config entry (HTTP $status):" >&2
  cat "$tmp" >&2 || true
  rm -f "$tmp"
  return 1
}

delete_device() {
  local devices_json candidate device_id config_entry_id

  devices_json="$(get_devices || true)"

  if [[ "$DEBUG" == "1" ]]
  then
    echo "DEBUG: raw response from get_devices():" >&2
    echo "$devices_json" >&2
  fi

  if ! jq -e 'select(.id == 1 and .type == "result" and .success == true)' \
    <<<"$devices_json" > /dev/null
  then
    echo "ERROR: did not find a successful device_registry/list response (id=1)" >&2
    if [[ "$DEBUG" == "1" ]]
    then
      echo "DEBUG: full response stream above." >&2
    fi
    return 1
  fi

  if [[ "$DEBUG" == "1" ]]
  then
    echo "DEBUG: total devices:" >&2
    jq -r '
      select(.id == 1 and .type == "result" and .success == true)
      | "count=\(.result | length)"
    ' <<<"$devices_json" >&2

    echo "DEBUG: mobile_app devices:" >&2
    jq -r '
      select(.id == 1 and .type == "result" and .success == true)
      | .result[]
      | select(
          (.identifiers // [])
          | map(type == "array" and (.[0] // "") == "mobile_app")
          | any
        )
      | "- id=\(.id) name=\"\(.name // "")\" name_by_user=\"\(.name_by_user // "")\" identifiers=\(.identifiers // []) config_entries=\(.config_entries // []) primary_config_entry=\(.primary_config_entry // "null")"
    ' <<<"$devices_json" >&2 || true
  fi

  candidate="$(select_mobile_app_device "$DEVICE_NAME" <<<"$devices_json" | head -n 1)"

  if [[ -z "$candidate" ]]
  then
    echo "No mobile_app device found for name: $DEVICE_NAME" >&2

    if [[ "$DEBUG" == "1" ]]
    then
      echo "DEBUG: devices with that exact name (any integration):" >&2
      jq -c --arg name "$DEVICE_NAME" '
        select(.id == 1 and .type == "result" and .success == true)
        | .result[]
        | select((.name // "") == $name or (.name_by_user // "") == $name)
      ' <<<"$devices_json" >&2 || true
    fi

    return 1
  fi

  device_id="$(jq -r '.id' <<<"$candidate")"
  config_entry_id="$(jq -r '.primary_config_entry // (.config_entries[0] // "")' <<<"$candidate")"

  if [[ -z "$config_entry_id" || "$config_entry_id" == "null" ]]
  then
    echo "Found mobile_app device '$DEVICE_NAME' (device_id=$device_id) but no config entry id; cannot delete safely." >&2
    if [[ "$DEBUG" == "1" ]]
    then
      echo "DEBUG: candidate:" >&2
      echo "$candidate" | jq >&2 || true
    fi
    return 1
  fi

  echo "Deleting mobile_app device '$DEVICE_NAME' via config entry $config_entry_id (device_id=$device_id)..."

  if delete_config_entry "$config_entry_id"
  then
    echo "Success: config entry $config_entry_id deleted, mobile_app device should be removed."
    return 0
  fi

  echo "Failed to delete config entry $config_entry_id." >&2
  return 1
}

echo "Deleting device '$DEVICE_NAME' from Home Assistant"
if ! delete_device
then
  echo "Device deletion failed (it might not exist), continuing anyway" >&2
fi

echo "Stopping go-hass-agent service"
systemctl --user stop go-hass-agent.service
trap "echo 'Restarting go-hass-agent service'; systemctl --user restart --no-block go-hass-agent.service" EXIT

echo "Re-registering go-hass-agent with Home Assistant"
go-hass-agent register --force --ignore-hass-urls \
  --server="$HASS_SERVER" --token="$HASS_TOKEN"
