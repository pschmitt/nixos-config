#!/usr/bin/env bash
#
# migrate-fnuc-to-lrz.sh — Data migration from fnuc to lrz
#
# Transfers:
#   1. Home Assistant VM: QCOW2 disk (sparse), NVRAM, and libvirt XML
#   2. /mnt/sda1: Media & camera storage (frigate, reolink; excludes dead Longhorn replicas)
#   3. /srv: All compose stacks and persistent service state (syslog-ng, smokeping, etc.)
#
# Modes:
#   --presync (default): Warm pre-transfer while fnuc workloads remain live
#   --final            : Stops VM and host services on fnuc before running final delta sync
#   --dry-run, -n      : Pass -n to rsync to preview operations without modifying target
#

set -euo pipefail

SOURCE_HOST="fnuc"
DEST_HOST="lrz"
DEST_USER="pschmitt"
SSH_KEY="/home/pschmitt/.ssh/id_ed25519"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -i "${SSH_KEY}")

DRY_RUN=0
MODE="presync" # presync | final
CONFIRM_FINAL=0
TARGET="all" # all | ha-vm | sda1 | srv

log() {
  echo -e "\033[1;34m[INFO]\033[0m $(date +'%Y-%m-%d %H:%M:%S') — $*"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $(date +'%Y-%m-%d %H:%M:%S') — $*"
}

err() {
  echo -e "\033[1;31m[ERROR]\033[0m $(date +'%Y-%m-%d %H:%M:%S') — $*" >&2
}

die() {
  err "$*"
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [TARGET]

Targets:
  all               Run migration for all components (ha-vm, sda1, srv) [default]
  ha-vm             Home Assistant OS VM disk, NVRAM, and libvirt XML
  sda1              /mnt/sda1 storage (frigate, reolink; excludes dead replicas)
  srv               /srv directories (syslog-ng, smokeping, netalertx, etc.)

Options:
  -n, --dry-run     Perform dry-run with rsync -n
  --presync         Warm pre-sync without stopping services (default; safe for live HA)
  --final           Final delta sync: stops services/VM on fnuc prior to sync (requires --confirm-final)
  --confirm-final   Explicit confirmation required when running --final to prevent accidental disruption
  --source <host>   Source host [default: fnuc]
  --dest <host>     Destination host [default: lrz]
  -h, --help        Show this help message
EOF
  exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --dry-run)
      DRY_RUN=1
      shift
      ;;
    --presync)
      MODE="presync"
      shift
      ;;
    --final)
      MODE="final"
      shift
      ;;
    --confirm-final)
      CONFIRM_FINAL=1
      shift
      ;;
    --source)
      [[ -n "${2:-}" ]] || die "--source requires a hostname"
      SOURCE_HOST="$2"
      shift 2
      ;;
    --dest)
      [[ -n "${2:-}" ]] || die "--dest requires a hostname"
      DEST_HOST="$2"
      shift 2
      ;;
    all | ha-vm | sda1 | srv)
      TARGET="$1"
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "Unknown argument: $1. Run with --help for usage."
      ;;
  esac
done

if [[ "$MODE" == "final" && $DRY_RUN -eq 0 && $CONFIRM_FINAL -eq 0 ]]; then
  die "SAFETY ABORT: --final mode will gracefully shut down the Home Assistant VM and stop Docker containers on \${SOURCE_HOST}! If you are performing the final live cutover, pass --confirm-final."
fi

RSYNC_FLAGS=("-aHAX" "--numeric-ids" "--info=progress2")
if [[ $DRY_RUN -eq 1 ]]; then
  RSYNC_FLAGS+=("-n")
fi

run_src_rsync() {
  local src="$1"
  local dst="$2"
  shift 2
  local extra_args=("$@")

  local rsync_cmd ssh_cmd
  printf -v ssh_cmd '%q ' ssh "${SSH_OPTS[@]}"
  printf -v rsync_cmd '%q ' sudo -n rsync "${RSYNC_FLAGS[@]}" "${extra_args[@]}" \
    -e "${ssh_cmd}" --rsync-path='sudo -n rsync' -- "${src}" "${DEST_USER}@${DEST_HOST}:${dst}"
  log "Executing rsync on ${SOURCE_HOST}: ${src} -> ${DEST_HOST}:${dst}"
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "${rsync_cmd}"
}

preflight_checks() {
  [[ "$SOURCE_HOST" != "$DEST_HOST" ]] || die "Source and destination must differ"
  log "Starting preflight checks..."
  log "Checking connectivity to source (${SOURCE_HOST}) and destination (${DEST_HOST})..."

  ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${SOURCE_HOST}" "hostname" >/dev/null 2>&1 || die "Cannot connect to ${SOURCE_HOST}"
  ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${DEST_HOST}" "hostname" >/dev/null 2>&1 || die "Cannot connect to ${DEST_HOST}"

  log "Verifying remote sudo and rsync on both hosts..."
  ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo -n rsync --version" >/dev/null 2>&1 || die "sudo rsync failed on ${SOURCE_HOST}"
  ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${DEST_HOST}" "sudo -n rsync --version" >/dev/null 2>&1 || die "sudo rsync failed on ${DEST_HOST}"

  log "Checking free space on ${DEST_HOST}..."
  ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "df -h / /mnt/sda1"
  log "Preflight checks passed."
}

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

migrate_srv() (
  log "=========================================================="
  log "Migrating /srv (syslog-ng, smokeping, netalertx, etc.)"
  log "=========================================================="

  # Stop active services on destination host that write to /srv
  local srv_units=(
    "syslog-ng.service"
    "smokeping.service"
    "docker-watchyourlan.service"
    "docker-ftpd.service"
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

source_virsh() {
  local command
  printf -v command '%q ' sudo -n env LC_ALL=C virsh -c qemu:///system "$@"
  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "$command"
}

source_vm_disk() {
  source_virsh domblklist home-assistant "$@" | awk '$1 == "vda" { print $2 }'
}

acquire_migration_lock() {
  # Hold one destination-side lock even when invoked manually from fnuc.
  # Closing the input pipe releases flock without killing an in-flight rsync.
  coproc MIGRATION_LOCK {
    ssh "${SSH_OPTS[@]}" "${DEST_HOST}" \
      "flock -n /var/lib/fnuc-migration/lock sh -c 'echo locked; cat >/dev/null'"
  }
  local lock_reply
  # shellcheck disable=SC2034 # Closed by the main EXIT trap via its allocated fd.
  exec {MIGRATION_LOCK_INPUT}>&"${MIGRATION_LOCK[1]}"
  if ! read -r -t 20 lock_reply <&"${MIGRATION_LOCK[0]}" || [[ "$lock_reply" != locked ]]
  then
    err "Another migration/backup holds the destination lock, or lock setup failed"
    return 1
  fi
}

prepare_final_cutover() {
  # All source writers must stop before *any* final dataset is copied.
  [[ "$TARGET" == all ]] || die "Final cutover requires target all so media and VM data are quiesced together"
  if [[ $DRY_RUN -eq 1 ]]
  then
    log "[DRY-RUN] Would inhibit presync, stop HA and source containers, then copy all datasets"
    return 0
  fi
  ssh "${SSH_OPTS[@]}" "${DEST_HOST}" \
    "touch /var/lib/fnuc-migration/cutover && sudo -n systemctl stop fnuc-migration-presync.timer"
  [[ "$(source_vm_disk)" == /var/lib/libvirt/images/haos-11.2-restored.qcow2 ]] || die "Resolve source snapshot chain before cutover"
  [[ "$(source_vm_disk --inactive)" == /var/lib/libvirt/images/haos-11.2-restored.qcow2 ]] || die "Resolve persistent source snapshot chain before cutover"
  local vm_state remaining=120
  vm_state=$(source_virsh domstate home-assistant)
  case "$vm_state" in
    running) source_virsh shutdown home-assistant ;;
    "shut off") ;;
    *) die "Unsafe source VM state for final cutover: ${vm_state}" ;;
  esac
  while [[ "$(source_virsh domstate home-assistant)" != "shut off" ]]
  do
    [[ $remaining -gt 0 ]] || die "HA did not stop; refusing final copies"
    sleep 2
    remaining=$((remaining - 2))
  done
  ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" 'sudo -n bash -se' <<'REMOTE'
containers=$(docker ps -q)
if [[ -n "$containers" ]]
then
  # Docker IDs are generated by Docker and contain no whitespace.
  docker stop $containers
fi
[[ -z "$(docker ps -q)" ]]
REMOTE
  warn "Source HA and containers are stopped for cutover. They remain stopped if a later copy fails."
}

migrate_ha_vm() (
  log "=========================================================="
  log "Migrating Home Assistant OS VM (Mode: ${MODE})"
  log "=========================================================="

  local vm_img="/var/lib/libvirt/images/haos-11.2-restored.qcow2"
  local vm_nvram="/var/lib/libvirt/qemu/nvram/home-assistant_VARS.fd"
  local overlay_img="/var/lib/libvirt/images/haos-presync-overlay.qcow2"
  local snapshot_attempted=""
  local vm_status=0
  local dest_state

  # Neither a failed status query nor paused/crashed guests permit a direct copy.
  dest_state=$(ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n env LC_ALL=C virsh -c qemu:///system domstate home-assistant")
  [[ "$dest_state" == "shut off" ]] || die "Destination HA VM must be shut off before copying"
  [[ "$(source_vm_disk)" == "$vm_img" ]] || die "Unexpected source disk/overlay; resolve the backing chain before copying"
  [[ "$(source_vm_disk --inactive)" == "$vm_img" ]] || die "Persistent source domain does not reference the expected base disk"

  snapshot_failure() {
    if [[ -n "$snapshot_attempted" ]]
    then
      err "Snapshot operation incomplete on ${SOURCE_HOST}. Preserve ${overlay_img}; it may contain live guest writes."
      err "Inspect live/inactive domblklist and block jobs before recovery. Do not remove the overlay or copy the base as a final disk."
    fi
  }
  trap 'vm_status=$?; snapshot_failure; exit "$vm_status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  # Ensure destination directories exist
  if [[ $DRY_RUN -eq 0 ]]
  then
    ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n mkdir -p /var/lib/libvirt/images /var/lib/libvirt/qemu/nvram"
  fi

  if [[ "$MODE" == "presync" ]]; then
    log "Presync mode: performing non-disruptive live external snapshot to pre-sync base QCOW2..."
    log "Dumping domain XML from ${SOURCE_HOST} for reference..."
    if [[ $DRY_RUN -eq 0 ]]; then
      source_virsh dumpxml home-assistant | ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n tee /var/lib/libvirt/qemu/home-assistant.xml >/dev/null"
    fi

    local vm_state
    vm_state=$(source_virsh domstate home-assistant)
    log "Current VM state on ${SOURCE_HOST}: ${vm_state}"

    if [[ "$vm_state" == "running" ]]; then
      local snap_name="presync-snapshot"

      log "Creating live disk-only snapshot overlay on ${SOURCE_HOST}..."
      if [[ $DRY_RUN -eq 0 ]]; then
        snapshot_attempted=1
        source_virsh snapshot-create-as home-assistant "${snap_name}" --disk-only --atomic --diskspec "vda,file=${overlay_img}" --no-metadata
        [[ "$(source_vm_disk)" == "$overlay_img" ]] || die "Snapshot did not switch the live source disk to the expected overlay"

        log "Transferring base QCOW2 disk image to ${DEST_HOST} (sparse, inplace)..."
        run_src_rsync "${vm_img}" "${vm_img}" "--sparse" "--inplace"

        log "Transferring NVRAM..."
        run_src_rsync "${vm_nvram}" "${vm_nvram}"

        log "Committing live snapshot overlay back into base disk on ${SOURCE_HOST}..."
        source_virsh blockcommit home-assistant vda --base "$vm_img" --top "$overlay_img" --active --pivot --shallow --verbose
        [[ "$(source_vm_disk)" == "$vm_img" ]] || die "Live source disk did not pivot back to the base; preserving overlay"
        [[ "$(source_vm_disk --inactive)" == "$vm_img" ]] || die "Persistent source domain still references an overlay; preserving it"
        # shellcheck disable=SC2029
        ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo -n rm -- ${overlay_img}"
        snapshot_attempted=""
      else
        log "[DRY-RUN] Would create snapshot overlay ${overlay_img}, rsync base image to ${DEST_HOST}, and blockcommit back to base"
      fi
    elif [[ "$vm_state" == "shut off" ]]
    then
      log "VM is not running on ${SOURCE_HOST} (${vm_state}); syncing QCOW2 directly..."
      run_src_rsync "${vm_nvram}" "${vm_nvram}"
      run_src_rsync "${vm_img}" "${vm_img}" "--sparse" "--inplace"
    else
      die "Refusing to copy disk from source VM state: ${vm_state}"
    fi

    log "HA VM pre-sync step completed successfully without disrupting running VM."
    return 0
  fi

  # From here on, MODE is "final"
  if [[ $DRY_RUN -eq 0 ]]; then
    log "Final mode: gracefully shutting down home-assistant VM on ${SOURCE_HOST}..."
    if [[ "$(source_virsh domstate home-assistant)" != "shut off" ]]
    then
      source_virsh shutdown home-assistant
    fi

    log "Waiting for VM to stop..."
    local timeout=60
    local vm_stopped=0
    while [[ $timeout -gt 0 ]]; do
      local state
      state=$(source_virsh domstate home-assistant)
      if [[ "$state" =~ "shut off" ]]; then
        log "VM successfully shut off."
        vm_stopped=1
        break
      fi
      sleep 2
      timeout=$((timeout - 2))
    done

    if [[ $vm_stopped -eq 0 ]]; then
      die "CRITICAL: VM did not shut off cleanly in 60s on ${SOURCE_HOST}! Refusing to copy live disk. Please stop the VM manually and re-run."
    fi

    # Disable pre-sync timer on destination host now that cutoff is reached
    log "Cutoff reached: disabling fnuc-migration-presync.timer on ${DEST_HOST}..."
    ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n systemctl stop fnuc-migration-presync.timer"
  else
    log "[DRY-RUN] Would shut down home-assistant VM on ${SOURCE_HOST} and disable presync timer on ${DEST_HOST}"
  fi

  # 1. Dump libvirt domain XML for reference
  log "Dumping domain XML from ${SOURCE_HOST}..."
  if [[ $DRY_RUN -eq 0 ]]; then
    source_virsh dumpxml home-assistant | ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo -n tee /var/lib/libvirt/qemu/home-assistant.xml >/dev/null"
  fi

  # 2. Transfer NVRAM from powered-off VM
  log "Transferring NVRAM from powered-off VM..."
  run_src_rsync "${vm_nvram}" "${vm_nvram}"

  # 3. Transfer QCOW2 disk image from powered-off VM
  log "Transferring QCOW2 disk image from powered-off VM (sparse)..."
  run_src_rsync "${vm_img}" "${vm_img}" "--sparse" "--inplace"

  log "Home Assistant VM migration step (${MODE}) completed successfully."
)

main() {
  log "Starting fnuc -> lrz data migration [Target: ${TARGET}, Mode: ${MODE}, DryRun: ${DRY_RUN}]"
  preflight_checks
  if [[ $DRY_RUN -eq 0 ]]
  then
    acquire_migration_lock
    # The coprocess input is held for the entire operation; EOF releases it.
    trap 'exec {MIGRATION_LOCK_INPUT}>&-' EXIT
    if [[ "$MODE" == presync ]]
    then
      ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "test ! -e /var/lib/fnuc-migration/cutover"
    fi
  fi
  if [[ "$MODE" == final ]]
  then
    prepare_final_cutover
  fi

  case "$TARGET" in
    all)
      migrate_sda1
      migrate_srv
      migrate_ha_vm
      ;;
    sda1)
      migrate_sda1
      ;;
    srv)
      migrate_srv
      ;;
    ha-vm)
      migrate_ha_vm
      ;;
  esac

  log "All selected migration tasks finished successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
