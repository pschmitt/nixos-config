# shellcheck shell=bash
# Concatenated after lib.sh, sda1.sh, srv.sh and ha-vm.sh; see lib.sh for why
# this has no shebang. This is the CLI entrypoint: argument parsing and the
# main() dispatcher.

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
      # shellcheck disable=SC2034 # used by lib.sh/sda1.sh/srv.sh/ha-vm.sh
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

main() {
  log "Starting ${SOURCE_HOST} -> ${DEST_HOST} data migration [Target: ${TARGET}, Mode: ${MODE}, DryRun: ${DRY_RUN}]"
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
