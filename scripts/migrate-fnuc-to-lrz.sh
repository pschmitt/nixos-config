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
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -i "${SSH_KEY}")

DRY_RUN=0
MODE="presync" # presync | final
CONFIRM_FINAL=0
TARGET="all"   # all | ha-vm | sda1 | srv

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
		SOURCE_HOST="$2"
		shift 2
		;;
	--dest)
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

	local rsync_cmd="sudo rsync ${RSYNC_FLAGS[*]} ${extra_args[*]} -e 'ssh ${SSH_OPTS[*]}' --rsync-path='sudo rsync' ${src} ${DEST_USER}@${DEST_HOST}:${dst}"
	log "Executing rsync on ${SOURCE_HOST}: ${src} -> ${DEST_HOST}:${dst}"
	# shellcheck disable=SC2029
	ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "${rsync_cmd}"
}

preflight_checks() {
	log "Starting preflight checks..."
	log "Checking connectivity to source (${SOURCE_HOST}) and destination (${DEST_HOST})..."

	ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${SOURCE_HOST}" "hostname" >/dev/null 2>&1 || die "Cannot connect to ${SOURCE_HOST}"
	ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${DEST_HOST}" "hostname" >/dev/null 2>&1 || die "Cannot connect to ${DEST_HOST}"

	log "Verifying remote sudo and rsync on both hosts..."
	ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo rsync --version" >/dev/null 2>&1 || die "sudo rsync failed on ${SOURCE_HOST}"
	ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 "${DEST_HOST}" "sudo rsync --version" >/dev/null 2>&1 || die "sudo rsync failed on ${DEST_HOST}"

	log "Checking free space on ${DEST_HOST}..."
	ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "df -h / /mnt/sda1"
	log "Preflight checks passed."
}

migrate_sda1() {
	log "=========================================================="
	log "Migrating /mnt/sda1 (frigate, reolink; excluding replicas)"
	log "=========================================================="

	# Ensure target mount is mounted and directory exists
	ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo mkdir -p /mnt/sda1"

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

migrate_srv() {
	log "=========================================================="
	log "Migrating /srv (syslog-ng, smokeping, netalertx, etc.)"
	log "=========================================================="

	if [[ "$MODE" == "final" && $DRY_RUN -eq 0 ]]; then
		log "Final mode: stopping docker containers on ${SOURCE_HOST}..."
		ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo docker stop \$(sudo docker ps -q) 2>/dev/null || true"
	fi

	ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo mkdir -p /srv"
	run_src_rsync "/srv/" "/srv/" "--delete"
	log "/srv migration completed."
}

migrate_ha_vm() {
	log "=========================================================="
	log "Migrating Home Assistant OS VM (Mode: ${MODE})"
	log "=========================================================="

	local vm_img="/var/lib/libvirt/images/haos-11.2-restored.qcow2"
	local vm_nvram="/var/lib/libvirt/qemu/nvram/home-assistant_VARS.fd"

	# Ensure destination directories exist
	ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo mkdir -p /var/lib/libvirt/images /var/lib/libvirt/qemu/nvram"

	if [[ "$MODE" == "presync" ]]; then
		log "Presync mode: VM disk/NVRAM copy is deferred until final cutover."
		log "The live VM on ${SOURCE_HOST} is NOT touched or read during pre-sync."
		log "Dumping domain XML from ${SOURCE_HOST} for reference..."
		if [[ $DRY_RUN -eq 0 ]]; then
			ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo virsh dumpxml home-assistant" | ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo tee /var/lib/libvirt/qemu/home-assistant.xml >/dev/null"
		fi
		log "HA VM pre-sync step completed (XML saved, disk copy deferred to cutoff)."
		return 0
	fi

	# From here on, MODE is "final"
	if [[ $DRY_RUN -eq 0 ]]; then
		log "Final mode: gracefully shutting down home-assistant VM on ${SOURCE_HOST}..."
		ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo virsh shutdown home-assistant 2>/dev/null || true"

		log "Waiting for VM to stop..."
		local timeout=60
		local vm_stopped=0
		while [[ $timeout -gt 0 ]]; do
			local state
			state=$(ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo virsh domstate home-assistant 2>/dev/null || echo 'unknown'")
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
		ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo systemctl disable --now fnuc-migration-presync.timer 2>/dev/null || true"
	else
		log "[DRY-RUN] Would shut down home-assistant VM on ${SOURCE_HOST} and disable presync timer on ${DEST_HOST}"
	fi

	# 1. Dump libvirt domain XML for reference
	log "Dumping domain XML from ${SOURCE_HOST}..."
	if [[ $DRY_RUN -eq 0 ]]; then
		ssh "${SSH_OPTS[@]}" "${SOURCE_HOST}" "sudo virsh dumpxml home-assistant" | ssh "${SSH_OPTS[@]}" "${DEST_HOST}" "sudo tee /var/lib/libvirt/qemu/home-assistant.xml >/dev/null"
	fi

	# 2. Transfer NVRAM from powered-off VM
	log "Transferring NVRAM from powered-off VM..."
	run_src_rsync "${vm_nvram}" "${vm_nvram}"

	# 3. Transfer QCOW2 disk image from powered-off VM
	log "Transferring QCOW2 disk image from powered-off VM (sparse)..."
	run_src_rsync "${vm_img}" "${vm_img}" "--sparse" "--inplace"

	log "Home Assistant VM migration step (${MODE}) completed successfully."
}

main() {
	log "Starting fnuc -> lrz data migration [Target: ${TARGET}, Mode: ${MODE}, DryRun: ${DRY_RUN}]"
	preflight_checks

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

main "$@"
