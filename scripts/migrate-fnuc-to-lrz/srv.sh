# shellcheck shell=bash
# Concatenated after lib.sh; see lib.sh for why this has no shebang.

migrate_srv() (
  log "=========================================================="
  log "Migrating /srv (syslog-ng, smokeping, netalertx, etc.)"
  log "=========================================================="

  # Stop active services on destination host that write to /srv
  local srv_units=(
    "syslog-ng.service"
    "smokeping.service"
    "watchyourlan.service"
    "ftpd.service"
  )
  local stopped_units=()
  local unit unit_state
  local srv_status=0

  restore_srv_units() {
    local restore_status=0
    for unit in "${stopped_units[@]}"; do
      log "Restarting ${unit} on ${DEST_HOST}..."
      # shellcheck disable=SC2029
      if ! ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n systemctl start ${unit}"; then
        err "Failed to restart ${unit} on ${DEST_HOST}; manual recovery required."
        restore_status=1
      fi
    done
    return "${restore_status}"
  }

  # Restore previously active services after success, transfer failure or interruption.
  # Keep this trap confined to the /srv operation's subshell.
  trap 'srv_status=$?; trap - EXIT; restore_srv_units || srv_status=1; exit "$srv_status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [[ $DRY_RUN -eq 0 ]]; then
    for unit in "${srv_units[@]}"; do
      # shellcheck disable=SC2029
      unit_state=$(ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "systemctl show --property=ActiveState --value ${unit}")
      case "$unit_state" in
        inactive | failed) continue ;;
        active | activating | reloading | deactivating) ;;
        *) die "Cannot establish state of ${unit} on ${DEST_HOST}: ${unit_state}" ;;
      esac
        log "Stopping ${unit} on ${DEST_HOST} during /srv transfer..."
        # Track before stopping so a failed/ interrupted stop is recovered too.
        stopped_units+=("${unit}")
        # shellcheck disable=SC2029
        ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n systemctl stop ${unit}"
    done
  fi

  if [[ $DRY_RUN -eq 0 ]]; then
    ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n mkdir -p /srv"
  fi
  run_src_rsync "/srv/" "/srv/" "--delete"

  log "/srv transfer completed; restoring destination services."
)

# vim: set ft=sh et ts=2 sw=2 :
