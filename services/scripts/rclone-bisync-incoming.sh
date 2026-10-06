main() {
  local config_path
  local rclone_workdir
  local system_lockfile
  local -a extra_args

  config_path=
  rclone_workdir=/var/cache/rclone/bisync
  system_lockfile=/var/cache/rclone/bisync/incoming.systemd.lock
  extra_args=()

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --config)
        if [[ -z "${2:-}" ]]
        then
          printf 'Missing value for --config\n' >&2
          return 2
        fi

        config_path="$2"
        shift 2
        ;;
      *)
        extra_args+=("$1")
        shift
        ;;
    esac
  done

  if [[ -z "$config_path" ]]
  then
    printf 'Missing required --config argument\n' >&2
    return 2
  fi

  mkdir -p "$rclone_workdir"

  # Runs every minute: skip this tick if the previous run is still going
  exec 9>"$system_lockfile"
  if ! flock -n 9
  then
    printf 'Previous Incoming bisync still running, skipping\n' >&2
    return 0
  fi

  # Narrow bisync of the scanner inbox only. The hourly Documents bisync
  # excludes /Incoming/ (the dir itself, so --remove-empty-dirs cannot drop it) so the two jobs never touch the same files.
  # --min-age skips files that are still being uploaded by the scanner.
  rclone bisync "/mnt/data/srv/syncthing/documents/Incoming" "drive:Documents/Incoming" \
    --config "$config_path" \
    --recover \
    --min-age 5s \
    --workdir "$rclone_workdir" \
    --verbose \
    "${extra_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
