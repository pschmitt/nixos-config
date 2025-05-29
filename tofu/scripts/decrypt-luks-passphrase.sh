#!/usr/bin/env bash

TARGET_HOST="${TARGET_HOST:-}"
TARGET_DISK="${TARGET_DISK:-root}"

if [[ -z "$TARGET_HOST" ]]
then
  echo "Missing TARGET_HOST env var"
  exit 2
fi

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

# sops
sops --decrypt --extract '["luks"]["'"${TARGET_DISK}"'"]' \
  "../../hosts/${TARGET_HOST}/luks.sops.yaml" | \
  tr -d '\n'
