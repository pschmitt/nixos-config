usage() {
  printf 'Usage: %s RUNTIME_CONFIG SEED_CONFIG\n' "$(basename "$0")" >&2
}

temporary_config=

initialize_config() {
  local runtime_config="$1"
  local seed_config="$2"
  local config_dir
  local lock_file

  umask 077
  config_dir="$(dirname "$runtime_config")"
  lock_file="${config_dir}/.rclone-config-init.lock"

  if [[ ! -d "$config_dir" ]]
  then
    printf 'Runtime config directory does not exist: %s\n' "$config_dir" >&2
    return 1
  fi

  exec 9>"$lock_file"
  flock 9

  if [[ -L "$runtime_config" ]] || [[ -e "$runtime_config" && ! -f "$runtime_config" ]]
  then
    printf 'Runtime config is not a regular file: %s\n' "$runtime_config" >&2
    return 1
  fi

  if [[ -e "$runtime_config" ]]
  then
    if [[ ! -s "$runtime_config" ]]
    then
      printf 'Runtime config exists but is empty: %s\n' "$runtime_config" >&2
      return 1
    fi

    chmod 0600 "$runtime_config"
    return 0
  fi

  if [[ ! -f "$seed_config" ]] || [[ ! -s "$seed_config" ]]
  then
    printf 'Seed config is missing, non-regular, or empty: %s\n' "$seed_config" >&2
    return 1
  fi

  temporary_config="$(mktemp "${config_dir}/.rclone-config.XXXXXXXX")"
  trap '[[ -z "${temporary_config:-}" ]] || rm -f -- "$temporary_config"' EXIT

  cp -- "$seed_config" "$temporary_config"
  if [[ ! -s "$temporary_config" ]]
  then
    printf 'Seed config copy is empty: %s\n' "$seed_config" >&2
    return 1
  fi

  chmod 0600 "$temporary_config"
  mv -T -- "$temporary_config" "$runtime_config"
  temporary_config=
  trap - EXIT
}

main() {
  if [[ "$#" -ne 2 ]]
  then
    usage
    return 2
  fi

  initialize_config "$1" "$2"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
