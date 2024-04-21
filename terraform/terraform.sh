#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

NIXOS_CONFIG_DIR="/etc/nixos"
TF_DIR="${NIXOS_CONFIG_DIR}/terraform"
SSH_IDENTITY_FILE="${HOME}/.ssh/id_ed25519"

sops_decrypt() {
  local dest="${TF_DIR:-${PWD}}"
  local age_key
  age_key=$(ssh-to-age -private-key < "$SSH_IDENTITY_FILE")

  SOPS_AGE_KEY="$age_key" sops -d "${dest}/terraform.tfvars.sops.json" \
    > "${dest}/terraform.tfvars.json"
}

cleanup() {
  if [[ -z "$KEEP_TFVARS" ]]
  then
    rm -vf "${TD_DIR:-$PWD}/terraform.tfvars.json"
  fi

  git -C "$NIXOS_CONFIG_DIR" reset --mixed &>/dev/null
}

trap 'cleanup' EXIT
sops_decrypt || exit 1
git -C "$NIXOS_CONFIG_DIR" add --intent-to-add .

terraform -chdir="${TF_DIR}" "$@"
