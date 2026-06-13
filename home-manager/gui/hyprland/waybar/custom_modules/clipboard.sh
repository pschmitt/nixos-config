#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $(basename "$0") format
EOF
}

main() {
  case "${1:-}" in
    format)
      printf '%s\n' '{"text": "📋", "alt": "clipboard", "class": "custom-clipboard", "tooltip": "Walker clipboard history" }'
      return 0
      ;;
    -h|--help|help)
      usage
      return 0
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
