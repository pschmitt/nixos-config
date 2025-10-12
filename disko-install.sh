#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

usage() {
  echo "Usage: $(basename "$0") HOSTNAME DISK"
}

main() {
  while [[ -n $* ]]
  do
    case "$1" in
      -h|--help|-\?)
        usage
        return 0
        ;;
      *)
        break
        ;;
    esac
  done

  local target_hostname="$1"
  local disk="$2"

  if [[ -z $target_hostname || -z $disk ]]
  then
    usage >&2
    return 2
  fi
  shift 2

  set -x
  sudo nix --experimental-features 'nix-command flakes' \
    run 'github:nix-community/disko/latest#disko-install' -- \
      --mode format \
      --flake ".#${target_hostname}" \
      --disk main "$disk" \
      "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  main "$@"
fi
