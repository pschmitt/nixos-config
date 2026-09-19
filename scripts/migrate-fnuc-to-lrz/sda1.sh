# shellcheck shell=bash
# Concatenated after lib.sh; see lib.sh for why this has no shebang.

migrate_sda1() {
  log "=========================================================="
  log "Migrating /mnt/sda1 (frigate, reolink; excluding replicas)"
  log "=========================================================="

  # Refuse --delete against a missing source mount or the destination root disk.
  ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "mountpoint -q /mnt/sda1"
  ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "mountpoint -q /mnt/sda1"

  # We sync specific live datasets: frigate, reolink
  # We exclude replicas, engine-binaries, longhorn-disk.cfg
  local excludes=(
    "--exclude=replicas"
    "--exclude=engine-binaries"
    "--exclude=longhorn-disk.cfg"
    "--exclude=mount-pvc.sh"
    "--delete"
  )

  run_src_rsync "/mnt/sda1/" "/mnt/sda1/" "${excludes[@]}"
  log "/mnt/sda1 migration completed."
}

# vim: set ft=sh et ts=2 sw=2 :
