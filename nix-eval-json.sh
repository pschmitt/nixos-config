#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

usage() {
  echo "Usage: $(basename "$0") TARGET_HOST CONFIG_PATH"
  echo
  echo "Example: $(basename "$0") x13 custom.username"
  echo "Example: $(basename "$0") rofl-10 'fileSystems.\"/mnt/data\"'"
}

ARGS=()
JQ_ARGS=()

while [[ -n $* ]]
do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -r|--raw*)
      JQ_ARGS+=(-r)
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

set -- "${ARGS[@]}"

TARGET_HOST="$1"
CONFIG_PATH="$2"

if [[ -z $TARGET_HOST ]]
then
  echo "Missing TARGET_HOST argument" >&2
  usage >&2
  exit 2
fi

if [[ -z $CONFIG_PATH ]]
then
  echo "Missing CONFIG_PATH argument" >&2
  usage >&2
  exit 2
fi

nix eval --json --no-warn-dirty --apply '
  n:
  let
    hp = n.pkgs.stdenv.hostPlatform;
  in {
    inherit (hp) system;
    res = n.config.'"${CONFIG_PATH}"';
  }
' ".#nixosConfigurations.${TARGET_HOST}" | jq -e "${JQ_ARGS[@]}" '.res'
