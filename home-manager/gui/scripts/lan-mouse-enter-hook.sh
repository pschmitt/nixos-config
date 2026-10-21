#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF_USAGE
Usage: $(basename "$0") PEER REMOTE_COMMAND
EOF_USAGE
}

main() {
  local peer
  local remote_command
  local runtime_dir
  local away_sentinel
  local incoming_sentinel

  if [[ $# -ne 2 ]]
  then
    printf 'Expected peer and remote command\n' >&2
    usage >&2
    return 2
  fi

  peer="$1"
  remote_command="$2"
  runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  away_sentinel="${runtime_dir}/lan-mouse-away"
  incoming_sentinel="${runtime_dir}/lan-mouse-incoming"

  if ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" "$remote_command"
  then
    rm -f "$incoming_sentinel"
    printf '%s\n' "$peer" > "$away_sentinel"
    lan-mouse-notify show "$peer"
  else
    rm -f "$away_sentinel" "$incoming_sentinel"
    lan-mouse-notify dismiss
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
