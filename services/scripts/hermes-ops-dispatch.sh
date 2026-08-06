# shellcheck shell=bash

HERMES_FLAKE_DIR="${HERMES_FLAKE_DIR:?}"
HERMES_GROUP="${HERMES_GROUP:?}"
HERMES_OPS_DIR="${HERMES_OPS_DIR:?}"
HERMES_USER="${HERMES_USER:?}"
NIXOS_REBUILD="${NIXOS_REBUILD:?}"

write_response() {
  local status="$1"
  local message="$2"
  local response_tmp="$HERMES_OPS_DIR/response.$$"

  printf '%s\n%s\n' "$status" "$message" > "$response_tmp"
  chown "$HERMES_USER:$HERMES_GROUP" "$response_tmp"
  chmod 0640 "$response_tmp"
  mv -f "$response_tmp" "$HERMES_OPS_DIR/response"
}

run_nixos_apply() {
  local log_path="$HERMES_OPS_DIR/nixos-apply.log"
  local message
  local output

  if [[ ! -f "$HERMES_FLAKE_DIR/flake.nix" ]]
  then
    write_response failed "No flake found at $HERMES_FLAKE_DIR/flake.nix"
    return 0
  fi

  : > "$log_path"
  chown "$HERMES_USER:$HERMES_GROUP" "$log_path"
  chmod 0640 "$log_path"

  if "${NIXOS_REBUILD}/bin/nixos-rebuild" switch \
    --flake "$HERMES_FLAKE_DIR#rofl-10" > "$log_path" 2>&1
  then
    write_response ok "NixOS switch completed for rofl-10"
    return 0
  fi

  output="$(tail -n 80 "$log_path")"
  printf -v message 'NixOS switch failed for rofl-10:\n%s' "$output"
  write_response failed "$message"
}

main() {
  local lock_path="$HERMES_OPS_DIR/lock"
  local request_path="$HERMES_OPS_DIR/request"
  local operation

  exec 9> "$lock_path"
  if ! flock -n 9
  then
    return 0
  fi

  if [[ ! -f "$request_path" ]]
  then
    return 0
  fi

  operation="$(head -n 1 "$request_path")"
  rm -f "$request_path"

  case "$operation" in
    nixos-apply)
      run_nixos_apply
      ;;
    *)
      write_response failed "Unsupported Hermes operation: $operation"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
