#!/usr/bin/env bash
#
# migrate-fnuc-to-lrz — Data migration from fnuc to lrz
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
# This file holds the shared state and helpers used by every migrate_*
# target; sda1.sh, srv.sh and ha-vm.sh each hold one target's logic, and
# main.sh is the CLI entrypoint. Nix concatenates them into one script at
# build time (see hosts/lrz/fnuc-migration.nix) — there is no runtime
# `source`, so only this file carries the shebang and `set -euo pipefail`.

set -euo pipefail

SOURCE_HOST="fnuc"
DEST_HOST="lrz"
DEST_USER="pschmitt"
SSH_KEY="/home/pschmitt/.ssh/id_ed25519"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -i "${SSH_KEY}")

# shellcheck disable=SC2034 # defaults for main.sh's option parser and the other target files
DRY_RUN=0
# shellcheck disable=SC2034
MODE="presync" # presync | final
# shellcheck disable=SC2034
CONFIRM_FINAL=0
# shellcheck disable=SC2034
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
  local -i deadline=$((SECONDS + 20)) remaining
  # shellcheck disable=SC2034 # Closed by the main EXIT trap via its allocated fd.
  exec {MIGRATION_LOCK_INPUT}>&"${MIGRATION_LOCK[1]}"
  # DEST_HOST's remote shell may print startup noise (e.g. a login banner)
  # before the real handshake line, so scan for "locked" rather than
  # assuming it's the first line read.
  while (( (remaining = deadline - SECONDS) > 0 ))
  do
    read -r -t "$remaining" lock_reply <&"${MIGRATION_LOCK[0]}" || break
    [[ "$lock_reply" == locked ]] && return 0
  done
  err "Another migration/backup holds the destination lock, or lock setup failed"
  return 1
}

# vim: set ft=sh et ts=2 sw=2 :
