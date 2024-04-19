#!/usr/bin/env bash

NIXOS_CONFIG_DIR="/etc/nixos"
git -C "$NIXOS_CONFIG_DIR" add --intent-to-add .
trap 'git -C "$NIXOS_CONFIG_DIR" reset --mixed &>/dev/null' EXIT
terraform -chdir="${NIXOS_CONFIG_DIR}/terraform" "$@"
