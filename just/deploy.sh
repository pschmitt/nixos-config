#!/usr/bin/env bash
set -euxo pipefail

TARGET_HOST="$1"
shift

# sops-install-secrets prints the SSH-derived GPG/age fingerprints during
# activation. They are public identifiers, but they end up in agent transcripts
# and the leaked-credentials note, so mask them.
redact_identifiers() {
  sed -E \
    -e 's/(with fingerprint )[[:alnum:]]+/\1<redacted>/' \
    -e 's/age1[a-z0-9]{50,}/age1<redacted>/g'
}

# Prebuilt closures skip flake evaluation and compilation on the target.
# nixos-rebuild rejects combining --store-path with --flake.
for deploy_arg in "$@"
do
  case "$deploy_arg" in
    --store-path|--store-path=*)
      if [[ -n "$TARGET_HOST" ]]
      then
        ssh "$TARGET_HOST" sudo nixos-rebuild switch --no-reexec --use-substitutes "$@" 2>&1 | redact_identifiers
      else
        sudo nixos-rebuild switch --no-reexec --use-substitutes "$@" 2>&1 | redact_identifiers
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
  ssh "$TARGET_HOST" sudo nixos-rebuild switch --flake "${BUILD_DIR}#${TARGET_HOST}" --use-substitutes "$@" 2>&1 | redact_identifiers
else
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
  BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh nixos)"
  trap 'rm -rf -- "$BUILD_DIR"' EXIT
  sudo nix run nixpkgs#nixos-rebuild -- switch --flake "${BUILD_DIR}#${TARGET_HOST}" "$@" 2>&1 | redact_identifiers
fi
