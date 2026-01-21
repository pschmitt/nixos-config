#!/usr/bin/env bash

BACKUP_DIR="${BACKUP_DIR:-/srv/evernote-backup/data/backups}"

set -x

prune_backups() {
  local KEEP=10
  echo "Pruning old backups - keeping the last ${KEEP} backups"

  # Below will always fail with: "cannot delete xxx: Directory not empty"
  # find "${BACKUP_DIR}" -type d -name 'evernote-*' -mtime +10 -print -delete

  local dir
  find "${BACKUP_DIR}" -maxdepth 1 -type d -name 'evernote-*' | \
    sort -r | tail -n +"$((KEEP + 1))" | while read -r dir
  do
    echo "🗑️ Pruning: $dir"
    /run/wrappers/bin/sudo rm -rf -- "$dir"
  done
}

sync_db() {
  evernote-backup sync
}

enex_export() {
  local now
  now=$(date -Iseconds)
  local backup_path="${BACKUP_DIR}/evernote-${now}"

  if evernote-backup export "$backup_path"
  then
    /run/wrappers/bin/sudo ln -sfv "$backup_path" "${BACKUP_DIR}/latest"
    return 0
  fi

  return 1
}

if sync_db
then
  echo "✅ Sync successful"
else
  echo "❌ Sync failed" >&2
  exit 1
fi

if enex_export
then
  echo "✅ Backup successful"
  prune_backups
else
  echo "❌ Backup failed" >&2
  exit 1
fi
