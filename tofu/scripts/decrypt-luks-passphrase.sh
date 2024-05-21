#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
TARGET_HOST="${TARGET_HOST:-rofl-02}"

# age
# AGENIX_DIR="${AGENIX_DIR:-/etc/nixos/secrets}"
# AGE_IDENTITY_FILE="${AGE_IDENTITY_FILE:-/home/pschmitt/.ssh/id_ed25519}"
#
# age --decrypt --identity "$AGE_IDENTITY_FILE" \
#   "${AGENIX_DIR}/${TARGET_HOST}/luks-passphrase-root.age" | \
#   tr -d '\n'

# sops
sops --decrypt --extract '["luks"]["root"]' \
  "../../hosts/${TARGET_HOST}/luks.sops.yaml" | \
  tr -d '\n'
