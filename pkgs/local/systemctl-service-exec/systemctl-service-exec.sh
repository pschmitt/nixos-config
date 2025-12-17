#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: ${0##*/} <unit>

Get an interactive shell inside the namespace + environment of a systemd service,
similar to "docker exec -it <container> bash".

Supports services with DynamicUser=true (uses the running MainPID's uid/gid).

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

get_uid_gid_from_pid() {
  local pid="$1"

  if [[ ! -r "/proc/${pid}/status" ]]
  then
    echo "could not read /proc/${pid}/status" >&2
    return 1
  fi

  local uid
  if ! uid="$(
    awk '
      $1 == "Uid:" {
        print $2
        exit
      }
    ' "/proc/${pid}/status"
  )" || [[ -z $uid ]]
  then
    echo "could not extract uid from /proc/${pid}/status" >&2
    return 1
  fi

  local gid
  if ! gid="$(
    awk '
      $1 == "Gid:" {
        print $2
        exit
      }
    ' "/proc/${pid}/status"
  )" || [[ -z $gid ]]
  then
    echo "could not extract gid from /proc/${pid}/status" >&2
    return 1
  fi

  echo "$uid $gid"
}

get_groups_from_pid() {
  local pid="$1"

  if [[ ! -r "/proc/${pid}/status" ]]
  then
    echo "could not read /proc/${pid}/status" >&2
    return 1
  fi

  local groups
  if ! groups="$(
    awk '
      $1 == "Groups:" {
        for (i = 2; i <= NF; i++) {
          if ($i != "") {
            printf "%s%s", sep, $i
            sep = ","
          }
        }
        print ""
        exit
      }
    ' "/proc/${pid}/status"
  )"
  then
    echo "could not extract groups from /proc/${pid}/status" >&2
    return 1
  fi

  echo "$groups"
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
  if ! user="$(systemctl show -p User --value "$unit" 2>/dev/null)" || \
     [[ -z "$user" ]]
  then
    user=root
  fi

  local uid gid uid_gid
  if uid_gid="$(get_uid_gid "$user" 2>/dev/null)"
  then
    read -r uid gid <<< "$uid_gid"
  else
    # For DynamicUser=true services, User= often does not exist in NSS (/etc/passwd),
    # but the running process still has a real numeric uid/gid.
    read -r uid gid <<< "$(get_uid_gid_from_pid "$pid")"
  fi

  local groups
  groups="$(get_groups_from_pid "$pid")"

  local bash
  bash=$(command -v bash)

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
    "SERVICE_GROUPS=$groups" \
    "BASH=$bash" \
    "SETPRIV=$(command -v setpriv)" \
    nsenter \
      --target "$pid" \
      --mount --uts --ipc --net --pid \
      "$bash" --noprofile --norc -c '
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
        if [[ -n "$SETPRIV" && -x "$SETPRIV" ]]
        then
          exec "$SETPRIV" \
            --reuid "$SERVICE_UID" \
            --regid "$SERVICE_GID" \
            --groups "$SERVICE_GROUPS" \
            "$BASH"
        fi

        # Fallback: su, using numeric uid if no username
        exec /run/wrappers/bin/su -s "$BASH" "#${SERVICE_UID}"
      '
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -euo pipefail
  main "$@"
fi
