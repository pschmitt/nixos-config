#!/usr/bin/env bash

set -euo pipefail

# Ensure we are in the script's directory (repo root)
cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [ARGS...]

Commands:
  iso [HOST]            Build ISO image (default: iso)
  sd-image [HOST]       Build SD image (default: pica4)

Options:
  -h, --help            Show this help message

Examples:
  $(basename "$0") iso
  $(basename "$0") iso iso-xmr
  $(basename "$0") sd-image
  $(basename "$0") sd-image pica4
EOF
}

cmd_iso() {
  local host="${1:-iso}"
  if [[ "$host" == "-h" || "$host" == "--help" ]]
  then
    usage
    exit 0
  fi
  rm -f result
  echo "Building ISO for host '$host'..."
  nix build ".#nixosConfigurations.${host}.config.system.build.isoImage"
  if command -v tree >/dev/null
  then
    tree result
  fi
}

cmd_sd_image() {
  local host="${1:-pica4}"
  if [[ "$host" == "-h" || "$host" == "--help" ]]
  then
    usage
    exit 0
  fi
  rm -f result
  echo "Building SD image for host '$host'..."
  nix build --print-build-logs ".#nixosConfigurations.${host}.config.system.build.sdImage"
  if command -v tree >/dev/null
  then
    tree result
  fi
}

main() {
  if [[ $# -eq 0 ]]
  then
    usage
    exit 1
  fi

  case "$1" in
    iso)
      shift
      cmd_iso "$@"
      ;;
    sd-image)
      shift
      cmd_sd_image "$@"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown command '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
