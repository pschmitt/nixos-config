#!/usr/bin/env bash

ssh_host=rofl-15

cleanup() {
  ssh -S "$socket_dir/control" -O exit -- "$ssh_host" >/dev/null 2>&1 || true
  rm -r -- "$socket_dir"
}

main() {
  local arg
  local custom_url="${CIRCUS_URL:-}"
  local custom_key="${CIRCUS_API_KEY:-}"
  local port
  local token="${CIRCUS_API_KEY:-}"
  local status=0

  if [[ $# -eq 0 || "${1:-}" == help ]]
  then
    exec @CIRCUSCTL@ "$@"
  fi

  for arg in "$@"
  do
    case "$arg" in
      -h|--help|-V|--version) exec @CIRCUSCTL@ "$@" ;;
      --url|--url=*) custom_url=1 ;;
      --api-key|--api-key=*) custom_key=1 ;;
    esac
  done

  # Custom servers must use credentials from the caller.
  if [[ -n "$custom_url" ]]
  then
    exec @CIRCUSCTL@ "$@"
  fi

  if [[ -z "$custom_key" ]]
  then
    if ! token="$(rbw get --field 'API Token' @VAULT_ENTRY@)" || [[ -z "$token" ]]
    then
      printf 'circusctl: could not read the Circus API token from rbw\n' >&2
      return 1
    fi
  fi

  port="$(python3 - <<'PYTHON'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PYTHON
  )" || return
  socket_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/circusctl.XXXXXX")" || return
  trap cleanup EXIT

  if ! ssh -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes \
    -M -S "$socket_dir/control" -fNT -L "127.0.0.1:$port:127.0.0.1:3000" -- "$ssh_host"
  then
    printf 'circusctl: could not connect to Circus over SSH\n' >&2
    return 1
  fi

  CIRCUS_URL="http://127.0.0.1:$port" CIRCUS_API_KEY="$token" @CIRCUSCTL@ "$@" || status=$?
  return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
