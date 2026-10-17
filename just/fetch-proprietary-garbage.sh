#!/usr/bin/env bash

set -euo pipefail

get_blobs_credentials() {
  local item='blobs.brkn.lol private downloads'
  local username password

  if ! username=$(rbw get --exact --field username "$item") ||
    ! password=$(rbw get --exact "$item")
  then
    printf 'Could not read blobs.brkn.lol credentials from rbw\n' >&2
    return 1
  fi

  export BLOBS_USERNAME="$username"
  export BLOBS_PASSWORD="$password"
}

main() {
  local arg use_rbw=1

  for arg in "$@"
  do
    case "$arg" in
      --auth|--username|--password)
        use_rbw=
        ;;
    esac
  done

  if [[ -n "$use_rbw" &&
    -z "${BLOBS_BASIC_AUTH:-}" &&
    -z "${BLOBS_AUTH:-}" &&
    -z "${BLOBS_USERNAME:-}" &&
    -z "${BLOBS_PASSWORD:-}" ]]
  then
    get_blobs_credentials
  fi

  exec ./scripts/fetch-proprietary-garbage.sh "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
