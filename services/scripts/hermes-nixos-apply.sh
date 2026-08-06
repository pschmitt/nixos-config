# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0") [--restart-nixos-upgrade]

Request a privileged NixOS operation through the Hermes operations service.
EOF
}

wait_for_result() {
  local response_path="$1"
  local timeout_seconds="$2"
  local deadline=$((SECONDS + timeout_seconds))

  while ((SECONDS < deadline))
  do
    if [[ -f "$response_path" ]]
    then
      case "$(head -n 1 "$response_path")" in
        ok)
          tail -n +2 "$response_path"
          return 0
          ;;
        failed)
          tail -n +2 "$response_path" >&2
          return 1
          ;;
      esac
    fi

    sleep 1
  done

  printf 'Timed out waiting for the Hermes operations service\n' >&2
  return 1
}

main() {
  local ops_dir="${HERMES_OPS_DIR:-/srv/hermes/ops}"
  local request_path="$ops_dir/request"
  local response_path="$ops_dir/response"
  local request_tmp="$ops_dir/request.$$"
  local timeout_seconds="${HERMES_OPS_TIMEOUT_SECONDS:-1800}"
  local operation=nixos-apply

  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      --restart-nixos-upgrade)
        operation=nixos-upgrade-restart
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  if [[ -e "$request_path" ]]
  then
    printf 'Another Hermes operation is already queued\n' >&2
    return 1
  fi

  rm -f "$response_path"
  printf '%s\n' "$operation" > "$request_tmp"
  chmod 0600 "$request_tmp"
  mv "$request_tmp" "$request_path"

  wait_for_result "$response_path" "$timeout_seconds"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
