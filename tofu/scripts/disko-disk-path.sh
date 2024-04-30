#!/usr/bin/env bash

TARGET_HOST="${TARGET_HOST:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_USER="${REMOTE_USER:-root}"
DISK="${DISK:-/dev/disk/by-label/cloudimg-rootfs}"
DISK_PATH_CRITERIA="${DISK_PATH_CRITERIA:-by-id}"

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

if ! DISK_PATH=$(./absolute-disk-path.sh \
  --remote-host "$REMOTE_HOST" \
  --remote-user "$REMOTE_USER" \
  --criteria "$DISK_PATH_CRITERIA" \
  "$DISK")
then
  echo "Failed to resolve disk path ($DISK_PATH_CRITERIA) for $DISK on $REMOTE_HOST" >&2
  exit 1
fi

echo "Resolved disk path ($DISK_PATH_CRITERIA) for $DISK on $REMOTE_HOST to $DISK_PATH"

DISK_PATH_FILE=$(readlink -m "../../hosts/$TARGET_HOST/disk-path")
echo -n "$DISK_PATH" | tr -d '\n' > "$DISK_PATH_FILE"
# NOTE We need to git add here, otherwise nix will not pick up the file
git add --intent-to-add "$DISK_PATH_FILE"
