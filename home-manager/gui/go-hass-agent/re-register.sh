#!/usr/bin/env bash

set -uo pipefail

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

ENV_FILE="/run/secrets/rendered/go-hass-agent.env"
if [[ -f "$ENV_FILE" ]]
then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

SERVER="${HASS_SERVER:-}"
TOKEN="${HASS_TOKEN:-}"

if [[ -z "$SERVER" || -z "$TOKEN" ]]
then
  read -r SERVER TOKEN <<<"$(yq -r '
    .registration | "\(.server) \(.token)"
  ' ./preferences.toml)"
fi

if [[ -z "$SERVER" || -z "$TOKEN" ]]
then
  echo "Error: Server or token is missing (env + preferences)" >&2
  exit 1
fi

echo "Deleting device"
./delete-device.sh

echo "Stopping go-hass-agent service"
sudo systemctl stop go-hass-agent.service
trap "echo 'Restarting go-hass-agent service'; sudo systemctl restart --no-block go-hass-agent.service" EXIT

echo "Re-registering go-hass-agent with Home Assistant"
go-hass-agent register --force --ignore-hass-urls --server="$SERVER" --token="$TOKEN"
