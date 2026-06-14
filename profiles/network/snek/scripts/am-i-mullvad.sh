# am-i-mullvad — query Mullvad's connection-check endpoint
# (https://mullvad.net/en/check).
#
# Wrapped by writeShellApplication: shebang, `set -euo pipefail` and PATH
# (curl, jq via runtimeInputs) are injected by Nix.

usage() {
  cat <<EOF
Usage: $(basename "$0") [-j|--json] [curl-options...]

Check whether the current connection exits through Mullvad.
EOF
}

main() {
  local url="https://am.i.mullvad.net"
  local json=""

  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    -j|--json)
      shift
      url+="/json"
      json=1
      ;;
    *)
      url+="/connected"
      ;;
  esac

  if [[ -n "$json" ]]
  then
    curl -fsSL "$url" "$@" | jq -e '.'
  else
    curl -fsSL "$url" "$@"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
