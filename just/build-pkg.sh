#!/usr/bin/env bash
set -euxo pipefail

PKG="$1"
TARGET_HOST="${2:-}"
if [[ -z "$TARGET_HOST" ]]
then
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
fi
echo "Building pkg '${PKG}' for host '${TARGET_HOST}'"
nix build ".#nixosConfigurations.${TARGET_HOST}.pkgs.${PKG}"
