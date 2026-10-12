#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") ENTRY --cdp-url URL --page-id ID [--rp-id RP_ID] [--timeout SECONDS]

Inject a passkey directly into Chromium and synchronize its counter with the vault.
Forwards to rbw passkey inject. The old HTTP credential server is retired.
EOF
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    "")
      usage >&2
      return 2
      ;;
  esac

  rbw passkey inject "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
