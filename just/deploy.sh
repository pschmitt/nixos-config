#!/usr/bin/env bash
set -euxo pipefail

TARGET_HOST="$1"
shift

# Prebuilt closures skip flake evaluation and compilation on the target.
# nixos-rebuild rejects combining --store-path with --flake.
for deploy_arg in "$@"
do
  case "$deploy_arg" in
    --store-path|--store-path=*)
      if [[ -n "$TARGET_HOST" ]]
      then
        ssh "$TARGET_HOST" sudo nixos-rebuild switch --no-reexec --use-substitutes "$@"
      else
        sudo nixos-rebuild switch --no-reexec --use-substitutes "$@"
      fi
      exit 0
      ;;
  esac
done

if [[ -f /etc/profile.d/nix.sh ]]
then
  # shellcheck source=/dev/null
  source /etc/profile.d/nix.sh
fi

if [[ -n "$TARGET_HOST" ]]
then
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh --host "$TARGET_HOST" nixos)"
  trap 'ssh "$TARGET_HOST" rm -rf -- "$BUILD_DIR"' EXIT
  ssh "$TARGET_HOST" sudo nixos-rebuild switch --flake "${BUILD_DIR}#${TARGET_HOST}" --use-substitutes "$@"
else
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh nixos)"
  trap 'rm -rf -- "$BUILD_DIR"' EXIT
  sudo nix run nixpkgs#nixos-rebuild -- switch --flake "${BUILD_DIR}#${TARGET_HOST}" "$@"
fi
