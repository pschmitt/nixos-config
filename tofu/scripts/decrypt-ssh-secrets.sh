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


copy_user_keypair() {
  local key_type="$1"
  local ssh_user="pschmitt"
  local ssh_user_dir="./home/${ssh_user}/.ssh"

  local base_extract='["users"]["'"${ssh_user}"'"]["ssh"]["'"${key_type}"'"]'
  local base_name="${ssh_user_dir}/id_${key_type}"

  install -d -m 0700 "$ssh_user_dir"

  local key_kind tmp mode dest
  for key_kind in privkey pubkey
  do
    dest="$base_name"
    mode=600

    if [[ "$key_kind" == "pubkey" ]]
    then
      dest="${dest}.pub"
      mode=644
    fi

    tmp="$(mktemp)"
    if sops -d --extract "${base_extract}[\"${key_kind}\"]" "$SOPS_FILE" > "$tmp" 2>/dev/null
    then
      install -m "$mode" "$tmp" "$dest"
      sed -i '$a\' "$dest"
    fi

    rm -f "$tmp"
  done
}

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

copy_user_keypair "ed25519"
copy_user_keypair "rsa"

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
