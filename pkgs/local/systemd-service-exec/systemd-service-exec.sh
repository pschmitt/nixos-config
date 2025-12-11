#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: ${0##*/} <unit>

Get an interactive shell inside the namespace + environment of a systemd service,
similar to "docker exec -it <container> bash".

Examples:
  ${0##*/} radarr
  ${0##*/} radarr.service
EOF
}

get_unit_name() {
  local unit="$1"

  case "$unit" in
    *.service)
      echo "$unit"
    ;;
    *)
      echo "${unit}.service"
    ;;
  esac
}

# returns "<uid> <gid>" for a given user
get_uid_gid() {
  local user="$1"

  local uid
  if ! uid="$(id --real --user "$user")" || [[ -z "$uid" ]]
  then
    echo "could not resolve user '$user' via id" >&2
    return 1
  fi

  local gid
  if ! gid="$(id --real --group "$user")" || [[ -z "$gid" ]]
  then
    echo "could not resolve group for user '$user' via id" >&2
    return 1
  fi

  echo "$uid $gid"
}

main() {
  case "$1" in
    -h|--help)
      usage
      return 0
      ;;
  esac

  local svc="$1"

  if [[ -z "$svc" ]]
  then
    usage >&2
    return 2
  fi

  local unit
  unit="$(get_unit_name "$svc")"

  local pid
  pid="$(systemctl show -p MainPID --value "$unit" 2>/dev/null || true)"

  if [[ -z "$pid" || "$pid" == "0" ]]
  then
    echo "unit not running or not found: $unit" >&2
    return 1
  fi

  local user
  if ! user="$(systemctl show -p User --value "$unit" 2>/dev/null)" || [[ -z $user ]]
  then
    user=root
  fi

  local uid gid
  read -r uid gid <<< "$(get_uid_gid "$user")"

  # Shell inside the service's namespaces.
  # We pass SERVICE_* via env, then inside:
  #   - import /proc/$SERVICE_PID/environ
  #   - drop to SERVICE_UID:SERVICE_GID
  #   - exec bash
  sudo env \
    "SERVICE_PID=$pid" \
    "SERVICE_UID=$uid" \
    "SERVICE_GID=$gid" \
    "SERVICE_USER=$user" \
    "BASH=$(command -v bash)" \
    nsenter \
      --target "$pid" \
      --mount --uts --ipc --net --pid \
      "$(command -v bash)" --noprofile --norc -c '
        # Import the service environment from /proc/<pid>/environ
        # Each entry is "KEY=VALUE" separated by NUL
        while IFS= read -r -d "" LINE
        do
          case "$LINE" in
            *=*)
              export "$LINE"
            ;;
          esac
        done < "/proc/${SERVICE_PID}/environ"

        # Drop privileges to the service user
        if command -v setpriv &>/dev/null
        then
          exec setpriv \
            --reuid "$SERVICE_UID" \
            --regid "$SERVICE_GID" \
            --init-groups \
            "$BASH"
        fi

        # Fallback: su, using numeric uid if no username
        exec /run/wrappers/bin/su -s "$BASH" "${SERVICE_USER:-#${SERVICE_UID}}"
      '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -euo pipefail
  main "$@"
fi
