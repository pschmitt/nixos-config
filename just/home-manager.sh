#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/profile.d/nix.sh ]]
then
  source /etc/profile.d/nix.sh
fi
TARGET_HOST="${1:-}"
if [[ -z "$TARGET_HOST" ]]
then
  TARGET_HOST="${HOSTNAME:-$(hostname)}"
fi

# home-manager switch always activates on the machine this recipe runs on
# — there is no remote dispatch. Refuse to activate another host's profile
# locally (e.g. running 'just hm fnuc' while sitting on a different box).
ACTUAL_HOST="${HOSTNAME:-$(hostname)}"
RESOLVED_HOST="$TARGET_HOST"
if [[ "$RESOLVED_HOST" == "pschmitt" ]]
then
  RESOLVED_HOST="fnuc"
fi
if [[ "$RESOLVED_HOST" != "$ACTUAL_HOST" ]]
then
  echo "Refusing: 'just hm $TARGET_HOST' would activate that home-manager profile locally on '$ACTUAL_HOST', not on '$TARGET_HOST'." >&2
  echo "SSH to $TARGET_HOST and run 'just hm' there instead." >&2
  exit 1
fi

BUILD_DIR="$(./scripts/copy-to-nix-tmp.sh hm)"
trap "rm -rf '$BUILD_DIR'" EXIT

OLD_PROFILE="$(readlink -f ~/.local/state/nix/profiles/home-manager 2>/dev/null || true)"

nix_config='experimental-features = nix-command flakes'
if command -v gh >/dev/null 2>&1
then
  github_token="$(gh auth token 2>/dev/null || true)"
  if [[ -n "$github_token" ]]
  then
    nix_config+=$'\naccess-tokens = github.com='"$github_token"
  fi
fi

NIX_CONFIG="$nix_config" \
  nix run github:nix-community/home-manager -- \
    -b hm-backup \
    switch \
    --flake "${BUILD_DIR}#${TARGET_HOST}"

NEW_PROFILE="$(readlink -f ~/.local/state/nix/profiles/home-manager 2>/dev/null || true)"
if [[ -n "$OLD_PROFILE" && -n "$NEW_PROFILE" && "$OLD_PROFILE" != "$NEW_PROFILE" ]]
then
  nvd --color always diff "$OLD_PROFILE" "$NEW_PROFILE"
fi
