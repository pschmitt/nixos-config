#!/usr/bin/env bash

usage() {
  echo "Usage $(basename "$0") [--criteria CRITERIA] [TARGET_DEVICE]"
  echo
  echo "  --criteria CRITERIA: The desired path criteria to use to resolve the device to. Default: by-id"
  echo "  TARGET_DEVICE: The device to find the path for. Default: /dev/disk/by-label/cloudimg-rootfs"
}

fssh() {
  ssh \
    -o ControlMaster=no \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    "$@"
}

# findmnt-root() {
#   findmnt --noheadings --output SOURCE --target /
# }

main() {
  set -u -o pipefail

  local remote_host="${REMOTE_HOST:-}"
  local criteria="${CRITERIA:-by-id}"
  local ssh_args=()

  while [[ -n "$*" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -c|--criteria)
        criteria="$2"
        shift 2
        ;;
      -H|--host|-r|--remote-host)
        remote_host="$2"
        shift 2
        ;;
      --)
        shift
        break
        ssh_args=("$@")
        ;;
      *)
        break
        ;;
      esac
  done

  local target_device="${1:-/dev/disk/by-label/cloudimg-rootfs}"

  if [[ -z "$target_device" ]]
  then
    echo -e "\e[31mNo target device specified.\e[0m" >&2
    usage
    exit 2
  fi

  local partition_path
  if [[ -n "$remote_host" ]]
  then
    # shellcheck disable=SC2029
    partition_path=$(fssh "${ssh_args[@]}" "$remote_host" "readlink -e '$target_device'")
  else
    partition_path=$(readlink -e "$target_device")
  fi

  if [[ -z "$partition_path" ]]
  then
    echo -e "\e[31mNo device found for $target_device\e[0m" >&2
    exit 1
  fi

  local device_path
  device_path=$(sed -r 's/p?[0-9]+$//' <<< "$partition_path")

  local symlinks
  if [[ -n "$remote_host" ]]
  then
    symlinks=$(fssh "${ssh_args[@]}" "$remote_host" "find /dev/disk -type l -exec test {} -ef '$device_path' \; -print")
  else
    symlinks=$(find /dev/disk -type l -exec test {} -ef "$device_path" \; -print)
  fi

  echo -e "\e[34mFound device paths:\n$symlinks\e[0m" >&2

  grep -m 1 "$criteria" <<< "$symlinks"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
