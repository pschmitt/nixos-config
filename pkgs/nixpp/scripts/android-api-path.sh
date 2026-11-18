#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s PATH\n' "$(basename "$0")" >&2
}

main() {
  if [[ $# -ne 1 ]]
  then
    usage
    return 2
  fi

  local guest_path
  if ! guest_path=$(realpath -m -- "$1")
  then
    printf 'Could not resolve path: %s\n' "$1" >&2
    return 1
  fi

  case "$guest_path" in
    /android)
      printf '/\n'
      ;;
    /android/*)
      local host_path
      if ! host_path=$(realpath -m -- "${guest_path#/android}")
      then
        printf 'Could not resolve Android path: %s\n' "$guest_path" >&2
        return 1
      fi
      printf '%s\n' "$host_path"
      ;;
    /home|/home/*|/nix|/nix/*)
      local runtime_path=${NIXPP_RUNTIME:-}
      local app_runtime=/android/data/data/dev.pschmitt.termux/files/home/.local/share/termuxpp-nix
      if [[ "$runtime_path" == /run/nixpp-runtime && "$runtime_path" -ef "$app_runtime" ]]
      then
        runtime_path=$app_runtime
      fi
      if [[ "$runtime_path" != /android/* ]]
      then
        printf 'NIXPP_RUNTIME must be an /android/... path\n' >&2
        return 1
      fi

      local host_runtime=${runtime_path#/android}
      local host_path
      if ! host_path=$(realpath -m -- "$host_runtime/root$guest_path")
      then
        printf 'Could not resolve guest path: %s\n' "$guest_path" >&2
        return 1
      fi
      local guest_root
      case "$guest_path" in
        /home|/home/*)
          guest_root=/home
          ;;
        /nix|/nix/*)
          guest_root=/nix
          ;;
      esac

      local mapped_root
      if ! mapped_root=$(realpath -m -- "$host_runtime/root$guest_root")
      then
        printf 'Could not resolve guest root: %s\n' "$guest_root" >&2
        return 1
      fi
      case "$host_path" in
        "$mapped_root"|"$mapped_root"/*)
          printf '%s\n' "$host_path"
          ;;
        *)
          printf 'Path escapes mapped guest root: %s\n' "$guest_path" >&2
          return 1
          ;;
      esac
      ;;
    *)
      printf '%s\n' "$guest_path"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
