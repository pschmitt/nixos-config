wait_for_lock() {
  local lockfile="$1"
  local timeout_seconds="$2"
  local deadline

  deadline=$((SECONDS + timeout_seconds))

  while [[ -f "$lockfile" ]]
  do
    local pid
    local cmdline

    pid="$(jq -r '.PID // empty' < "$lockfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && [[ -r "/proc/$pid/cmdline" ]]
    then
      cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
      if grep -q "rclone" <<< "$cmdline" && grep -q "bisync" <<< "$cmdline"
      then
        if (( SECONDS >= deadline ))
        then
          printf 'Timed out waiting for active bisync PID %s to finish\n' "$pid" >&2
          return 1
        fi

        printf 'Waiting for active bisync PID %s to finish\n' "$pid" >&2
        sleep 10
        continue
      fi
    fi

    printf 'Removing stale bisync lockfile %s\n' "$lockfile" >&2
    rm -f "$lockfile"
  done
}

main() {
  local config_path
  local lockfile
  local rclone_workdir
  local system_lockfile
  local -a extra_args

  config_path=
  lockfile=/var/cache/rclone/bisync/nextcloud_Documents..drive_Documents.lck
  rclone_workdir=/var/cache/rclone/bisync
  system_lockfile=/var/cache/rclone/bisync/nextcloud_Documents..drive_Documents.systemd.lock
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

  exec 9>"$system_lockfile"
  flock -w 10800 9

  wait_for_lock "$lockfile" 10800

  rclone bisync "nextcloud:Documents" "drive:Documents" \
    --config "$config_path" \
    --check-access \
    --check-filename .rclone-test.empty \
    --recover \
    --remove-empty-dirs \
    --workdir "$rclone_workdir" \
    --verbose \
    "${extra_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
