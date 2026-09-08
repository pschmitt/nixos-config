usage() {
  cat >&2 <<'EOF'
Usage: ryzenadj-tdp --info
       ryzenadj-tdp --stapm-limit=MW --fast-limit=MW --slow-limit=MW --apu-slow-limit=MW
EOF
}

is_valid_milliwatts() {
  local value="$1"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] && ((value >= 1000 && value <= 1000000))
}

main() {
  if [[ "$#" -eq 1 && "$1" == "--info" ]]
  then
    exec ryzenadj --info
  fi

  if [[ "$#" -ne 4 ]]
  then
    usage
    return 2
  fi

  declare -A seen=()
  local name
  local value
  local argument

  for argument in "$@"
  do
    case "$argument" in
      --stapm-limit=*)
        name=stapm
        value="${argument#*=}"
        ;;
      --fast-limit=*)
        name=fast
        value="${argument#*=}"
        ;;
      --slow-limit=*)
        name=slow
        value="${argument#*=}"
        ;;
      --apu-slow-limit=*)
        name=apu_slow
        value="${argument#*=}"
        ;;
      *)
        printf 'Unsupported argument: %s\n' "$argument" >&2
        usage
        return 2
        ;;
    esac

    if [[ -n "${seen[$name]:-}" ]]
    then
      printf 'Duplicate argument: %s\n' "$argument" >&2
      return 2
    fi

    if ! is_valid_milliwatts "$value"
    then
      printf 'TDP value must be between 1000 and 1000000 mW: %s\n' "$value" >&2
      return 2
    fi

    seen[$name]=1
  done

  for name in stapm fast slow apu_slow
  do
    if [[ -z "${seen[$name]:-}" ]]
    then
      printf 'Missing TDP limit: %s\n' "$name" >&2
      usage
      return 2
    fi
  done

  exec ryzenadj "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
