#!/usr/bin/env bash

openstack --os-cloud internal-employee-pschmitt server delete rofl-02 && sleep 10

NIXOS_CONFIG_DIR="/etc/nixos"
git -C "$NIXOS_CONFIG_DIR" add --intent-to-add .
trap 'git -C "$NIXOS_CONFIG_DIR" reset --mixed &>/dev/null' EXIT

BUCKET_NAME="terraform-state-heimat-dev"
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY <<< \
  "$(zhj s3::credentials "$BUCKET_NAME")"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

terraform -chdir="${NIXOS_CONFIG_DIR}/terraform" apply -auto-approve
