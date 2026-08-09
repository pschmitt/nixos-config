# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0") PLAN STALWART CONFIG RECOVERY_URL
EOF
}

recovery_pid=

start_recovery_server() {
  local stalwart_binary="$1"
  local config_file="$2"
  local recovery_password="$3"

  STALWART_RECOVERY_MODE=1 \
    STALWART_RECOVERY_ADMIN="nix-config:${recovery_password}" \
    runuser -u stalwart -- "$stalwart_binary" --config="$config_file" &
  recovery_pid=$!
}

stop_recovery_server() {
  if [[ -n "$recovery_pid" ]]
  then
    kill -TERM "$recovery_pid" 2>/dev/null || true
    wait "$recovery_pid" 2>/dev/null || true
    recovery_pid=
  fi
}

apply_plan() {
  local plan_file="$1"
  local recovery_url="$2"
  local recovery_password="$3"
  local attempt=0

  while (( attempt < 30 ))
  do
    ((attempt += 1))
    if STALWART_URL="$recovery_url" \
      STALWART_USER=nix-config \
      STALWART_PASSWORD="$recovery_password" \
      stalwart-cli apply --file "$plan_file"
    then
      return 0
    fi
    sleep 1
  done

  printf 'Timed out applying Stalwart network listener plan\n' >&2
  return 1
}

cleanup() {
  local exit_code="$1"

  stop_recovery_server
  if ! systemctl start stalwart
  then
    printf 'Failed to restart the normal Stalwart service\n' >&2
    exit_code=1
  fi

  return "$exit_code"
}

main() {
  local plan_file="${1:-}"
  local stalwart_binary="${2:-}"
  local config_file="${3:-}"
  local recovery_url="${4:-}"
  local recovery_password

  if [[ "$plan_file" == "-h" || "$plan_file" == "--help" ]]
  then
    usage
    return 0
  fi

  if [[ -z "$plan_file" || -z "$stalwart_binary" || -z "$config_file" || -z "$recovery_url" || -n "${5:-}" ]]
  then
    usage >&2
    return 2
  fi

  recovery_password="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  trap 'cleanup "$?"' EXIT

  systemctl stop stalwart
  start_recovery_server "$stalwart_binary" "$config_file" "$recovery_password"
  apply_plan "$plan_file" "$recovery_url" "$recovery_password"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
