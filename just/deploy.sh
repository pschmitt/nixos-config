#!/usr/bin/env bash
set -euxo pipefail

if [[ -f /etc/profile.d/nix.sh ]]
then
  source /etc/profile.d/nix.sh
fi
TARGET_HOST="$1"
shift

if [[ -n "$TARGET_HOST" ]]
then
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh --host "$TARGET_HOST" nixos)"
  trap "ssh '$TARGET_HOST' rm -rf '$BUILD_DIR'" EXIT
  ssh "$TARGET_HOST" sudo nixos-rebuild switch --flake "${BUILD_DIR}#${TARGET_HOST}" --use-substitutes "$@"
else
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh nixos)"
  trap "rm -rf '$BUILD_DIR'" EXIT
  sudo nix run nixpkgs#nixos-rebuild -- switch --flake "${BUILD_DIR}#${TARGET_HOST}" "$@"
fi
