#!/usr/bin/env bash

TARGET_HOST="${TARGET_HOST:-}"

if [[ -z "$TARGET_HOST" ]]
then
  echo "Missing TARGET_HOST env var"
  exit 2
fi

mkdir -p ./etc/ssh/initrd

# TODO ?
# umask 0177
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# sops --extract '["initrd_ssh_key"]' -d "$SCRIPT_DIR/secrets.yaml" >./var/lib/secrets/initrd_ssh_key
# restore umask
# umask 0022

# agenix
# AGENIX_DIR=/etc/nixos/secrets
# AGE_IDENTITY_FILE=/home/pschmitt/.ssh/id_ed25519
# SSH_HOST_KEYS=(
#   ssh_host_rsa_key
#   ssh_host_rsa_key.pub
#   ssh_host_ed25519_key
#   ssh_host_ed25519_key.pub
# )
#
# for FILE in "${SSH_HOST_KEYS[@]}"
# do
#   if [[ "$FILE" == *.pub ]]
#   then
#     umask 0133
#   else
#     umask 0177
#   fi
#
#   age --decrypt --identity "$AGE_IDENTITY_FILE" \
#     "${AGENIX_DIR}/${TARGET_HOST}/${FILE}.age" > "./etc/ssh/$FILE"
# done

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
