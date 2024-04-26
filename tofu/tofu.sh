#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

NIXOS_CONFIG_DIR="/etc/nixos"
TF_DIR="${NIXOS_CONFIG_DIR}/opentofu"
SSH_IDENTITY_FILE="${HOME}/.ssh/id_ed25519"

sops_decrypt() {
  local dest="${TF_DIR:-${PWD}}"
  local age_key
  age_key=$(ssh-to-age -private-key < "$SSH_IDENTITY_FILE")

  # FIXME naming the file tofu.tfvars.json does not work
  # only terraform.tfvars.json works
  # https://opentofu.org/docs/language/values/variables/#variable-definitions-tfvars-files
  SOPS_AGE_KEY="$age_key" sops -d "${dest}/terraform.tfvars.sops.json" \
    > "${dest}/terraform.tfvars.json"
}

cleanup() {
  if [[ -z "$KEEP_TFVARS" ]]
  then
    rm -vf "${TD_DIR:-$PWD}/terraform.tfvars.json"
  fi

  git -C "$NIXOS_CONFIG_DIR" reset --mixed &>/dev/null
  # rm -rf "$NIXOS_CONFIG_TMP_DIR"
}

trap 'cleanup' EXIT

sops_decrypt || exit 1
git -C "$NIXOS_CONFIG_DIR" add --intent-to-add &>/dev/null
# NIXOS_CONFIG_TMP_DIR=$(zhj nix::clone-config) || exit 3
# pushd "$NIXOS_CONFIG_TMP_DIR" || exit 9

tofu -chdir="${TF_DIR}" "$@"
# RC=$?
# echo "NIXOS_CONFIG_TMP_DIR: $NIXOS_CONFIG_TMP_DIR" >&2
# exit "$RC"
