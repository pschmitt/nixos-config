#!/usr/bin/env bash

set -euo pipefail

TARGET_HOST="${TARGET_HOST:-}"

if [[ -z "$TARGET_HOST" ]]
then
  echo "Missing TARGET_HOST env var"
  exit 2
fi

mkdir -p ./etc/ssh/initrd
mkdir -p ./etc/crypttab.d/keyfiles

# sops
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SOPS_FILE="$(readlink -e "${SCRIPT_DIR}/../../hosts/${TARGET_HOST}/secrets.sops.yaml")"

umask 0133
sops -d --extract '["ssh"]["host_keys"]["rsa"]["pubkey"]' "$SOPS_FILE" > ./etc/ssh/ssh_host_rsa_key.pub
sops -d --extract '["ssh"]["host_keys"]["ed25519"]["pubkey"]' "$SOPS_FILE" > ./etc/ssh/ssh_host_ed25519_key.pub
sops -d --extract '["ssh"]["initrd_host_keys"]["rsa"]["pubkey"]' "$SOPS_FILE" > ./etc/ssh/initrd/ssh_host_rsa_key.pub
sops -d --extract '["ssh"]["initrd_host_keys"]["ed25519"]["pubkey"]' "$SOPS_FILE" > ./etc/ssh/initrd/ssh_host_ed25519_key.pub

umask 0177
sops -d --extract '["ssh"]["host_keys"]["rsa"]["privkey"]' "$SOPS_FILE" > ./etc/ssh/ssh_host_rsa_key
sops -d --extract '["ssh"]["host_keys"]["ed25519"]["privkey"]' "$SOPS_FILE" > ./etc/ssh/ssh_host_ed25519_key
sops -d --extract '["ssh"]["initrd_host_keys"]["rsa"]["privkey"]' "$SOPS_FILE" > ./etc/ssh/initrd/ssh_host_rsa_key
sops -d --extract '["ssh"]["initrd_host_keys"]["ed25519"]["privkey"]' "$SOPS_FILE" > ./etc/ssh/initrd/ssh_host_ed25519_key

# make sure our ssh keys end with a newline
for f in ./etc/ssh/* ./etc/ssh/initrd/*
do
  [[ -d "$f" ]] && continue # skip directories
  sed -i '$a\' "$f"
done

# Add data decryption keyfile
LUKS_SOPS_FILE="$(readlink -e "${SCRIPT_DIR}/../../hosts/${TARGET_HOST}/luks.sops.yaml")"
if [[ ! -r "$LUKS_SOPS_FILE" ]]
then
  echo "$LUKS_SOPS_FILE does not exist, no data file to decrypt" >&2
  exit 0
fi

if ! DATA_KEYFILE="$(sops -d --extract '["luks"]["data"]' "$LUKS_SOPS_FILE")"
then
  echo "No data keyfile found in $LUKS_SOPS_FILE" >&2
  exit 0
fi

umask 0177
printf '%s' "$DATA_KEYFILE" > ./etc/crypttab.d/keyfiles/data
