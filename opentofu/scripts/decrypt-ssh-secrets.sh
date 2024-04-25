#!/usr/bin/env bash

AGENIX_DIR=/etc/nixos/secrets
AGE_IDENTITY_FILE=/home/pschmitt/.ssh/id_ed25519
TARGET_HOST="${TARGET_HOST:-rofl-02}"

mkdir -p etc/ssh var/lib/secrets

# TODO ?
# umask 0177
# SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# sops --extract '["initrd_ssh_key"]' -d "$SCRIPT_DIR/secrets.yaml" >./var/lib/secrets/initrd_ssh_key
# restore umask
# umask 0022

SSH_HOST_KEYS=(
  ssh_host_rsa_key
  ssh_host_rsa_key.pub
  ssh_host_ed25519_key
  ssh_host_ed25519_key.pub
)

for FILE in "${SSH_HOST_KEYS[@]}"
do
  if [[ "$FILE" == *.pub ]]
  then
    umask 0133
  else
    umask 0177
  fi

  age --decrypt --identity "$AGE_IDENTITY_FILE" \
    "${AGENIX_DIR}/${TARGET_HOST}/${FILE}.age" > "./etc/ssh/$FILE"
done

# Determine disk path on the remote host
# CWD="$PWD"
# DISK_PATH_FILE="../hosts/${TARGET_HOST}/disk-path"
mkdir -p /tmp
DISK_PATH_FILE="./disk-path"
/etc/nixos/absolute-disk-path.sh > "$DISK_PATH_FILE"
# git  add --intent-to-add "$DISK_PATH_FILE"
