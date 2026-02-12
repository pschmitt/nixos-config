#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: syncthing-secrets.sh [OPTIONS] TARGET_HOST

Generates a Syncthing cert/key (and device ID) for TARGET_HOST.

Options:
  -p, --patch                 Write cert/key into hosts/TARGET_HOST/secrets.sops.yaml
  --update-devices-json       Write device ID into common/syncthing-devices.json
  --print-device-id           Print the computed device ID to stdout
  --print-json                Print JSON with cert/key/deviceID to stdout (no file writes)
  -h, --help                  Show this help

Examples:
  syncthing-secrets.sh --patch --update-devices-json rofl-10
  syncthing-secrets.sh --print-device-id rofl-10
  syncthing-secrets.sh --print-json rofl-10 | jq .
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1
  then
    printf 'Error: missing required command: %s\n' "$cmd" >&2
    return 2
  fi
}

repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
  (cd "$script_dir/.." >/dev/null 2>&1 && pwd -P)
}

gen_syncthing_material() {
  local temp_dir="$1"

  syncthing generate -H "$temp_dir" >/dev/null

  # "device-id" output is more stable than scraping config.xml.
  syncthing device-id --home "$temp_dir"
}

sops_set_string() {
  local sops_file="$1"
  local sops_key="$2"
  local value="$3"
  local value_json

  value_json="$(jq -en --arg v "$value" '$v')"
  sops set "$sops_file" "$sops_key" "$value_json" >/dev/null
}

update_devices_json() {
  local devices_json="$1"
  local target_host="$2"
  local device_id="$3"

  if [[ ! -f "$devices_json" ]]
  then
    printf 'Error: devices JSON not found: %s\n' "$devices_json" >&2
    return 4
  fi

  local tmp
  tmp="$(mktemp)"

  jq \
    --arg host "$target_host" \
    --arg id "$device_id" \
    '
      . as $root
      | ($root[$host] // {}) as $entry
      | .[$host] = ($entry + { id: $id })
    ' \
    "$devices_json" >"$tmp"

  chmod --reference="$devices_json" "$tmp"
  mv "$tmp" "$devices_json"
}

main() {
  local do_patch
  local do_update_devices_json
  local do_print_device_id
  local do_print_json
  local target_host

  do_patch=""
  do_update_devices_json=""
  do_print_device_id=""
  do_print_json=""
  target_host=""

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -h|--help|help)
        usage
        return 0
        ;;
      -p|--patch)
        do_patch=1
        shift
        ;;
      --update-devices-json)
        do_update_devices_json=1
        shift
        ;;
      --print-device-id)
        do_print_device_id=1
        shift
        ;;
      --print-json)
        do_print_json=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'Error: unknown option: %s\n' "$1" >&2
        return 2
        ;;
      *)
        if [[ -z "${target_host:-}" ]]
        then
          target_host="$1"
          shift
        else
          printf 'Error: unexpected argument: %s\n' "$1" >&2
          return 2
        fi
        ;;
    esac
  done

  if [[ -z "${target_host:-}" ]]
  then
    usage >&2
    return 2
  fi

  require_cmd jq
  require_cmd sops
  require_cmd syncthing

  local root
  root="$(repo_root)"
  cd "$root"

  local sops_file
  sops_file="hosts/${target_host}/secrets.sops.yaml"

  local devices_json
  devices_json="common/syncthing-devices.json"

  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT

  printf 'Generating Syncthing keys for %s...\n' "$target_host" >&2

  local device_id
  local cert
  local key
  device_id="$(gen_syncthing_material "$temp_dir")"
  cert="$(cat "$temp_dir/cert.pem")"
  key="$(cat "$temp_dir/key.pem")"

  if [[ -n "${do_print_device_id:-}" ]]
  then
    printf '%s\n' "$device_id"
  fi

  if [[ -n "${do_print_json:-}" ]]
  then
    jq -n \
      --arg deviceID "$device_id" \
      --arg cert "$cert" \
      --arg key "$key" \
      '{ syncthing: { cert: $cert, key: $key }, deviceID: $deviceID }'
  fi

  if [[ -n "${do_update_devices_json:-}" ]]
  then
    update_devices_json "$devices_json" "$target_host" "$device_id"
    printf 'Updated %s: %s -> %s\n' "$devices_json" "$target_host" "$device_id" >&2
  fi

  if [[ -n "${do_patch:-}" ]]
  then
    if [[ ! -f "$sops_file" ]]
    then
      printf 'Error: secrets file not found: %s\n' "$sops_file" >&2
      return 3
    fi

    printf 'Patching %s...\n' "$sops_file" >&2
    sops_set_string "$sops_file" '["syncthing"]["cert"]' "$cert"
    sops_set_string "$sops_file" '["syncthing"]["key"]' "$key"
    printf 'Patched %s (Device ID: %s)\n' "$sops_file" "$device_id" >&2
  fi

  if [[ -z "${do_patch:-}" && -z "${do_update_devices_json:-}" && -z "${do_print_device_id:-}" && -z "${do_print_json:-}" ]]
  then
    printf 'Nothing to do. Pick one or more of: --patch, --update-devices-json, --print-device-id, --print-json\n' >&2
    return 2
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ts=2 sw=2 et ft=sh:

