# netbird-force-routes — (re)apply or remove the netbird 10.0.0.0/8 routes on
# the main routing table.
#
# Wrapped by writeShellApplication: the shebang, `set -euo pipefail` and PATH
# (runtimeInputs, including the netbird-<instance> wrappers) are injected by
# Nix.

set -x

usage() {
  cat <<EOF
Usage: $(basename "$0") [--delete]

Add (default) or delete the netbird routes for the active interface.
EOF
}

add_routes() {
  local routes

  "$NB_BIN" routes list
  routes=$("$NB_BIN" routes list | awk '/Network: 10\./ { print $2 }' | sort -u)

  echo "Adding routes over $NB_INTERFACE_NAME for:"
  echo "${routes:-N/A}"

  xargs --verbose -I {} ip route add '{}' dev "$NB_INTERFACE_NAME" <<< "$routes"
}

delete_routes() {
  ip -j route show \
    | jq -er --arg nb "$NB_INTERFACE_NAME" '
        .[] | select(.dev == $nb and (.dst | test("^10\\."))) | .dst
      ' \
    | xargs --verbose -I {} ip route delete '{}' dev "$NB_INTERFACE_NAME"
}

main() {
  local action="add"

  NB_INSTANCE_NAME="${NB_INSTANCE_NAME:-wiit}"
  NB_INTERFACE_NAME="${NB_INTERFACE_NAME:-nb-$NB_INSTANCE_NAME}"
  NB_BIN="netbird-$NB_INSTANCE_NAME"

  case "${1:-}" in
    -h|--help)
      usage
      return 0
      ;;
    *undo|*remove|*del*|*rm*|*clear*)
      action="delete"
      ;;
  esac

  case "$action" in
    add)
      add_routes
      ;;
    delete)
      delete_routes
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
