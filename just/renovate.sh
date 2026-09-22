#!/usr/bin/env bash
set -euo pipefail

RENOVATE_TOKEN=${RENOVATE_TOKEN:-$(gh auth token)}
if [[ -z "${RENOVATE_REPOSITORIES:-}" ]]
then
  origin_url="$(git config --get remote.origin.url || true)"
  if [[ -z "$origin_url" ]]
  then
    echo "RENOVATE_REPOSITORIES is required (e.g. owner/repo)" >&2
    exit 1
  fi
  origin_path="$origin_url"
  if [[ "$origin_path" == *://* ]]
  then
    origin_path="${origin_path#*://}"
    origin_path="${origin_path#*/}"
  elif [[ "$origin_path" == *:* ]]
  then
    origin_path="${origin_path#*:}"
  fi
  origin_path="${origin_path%.git}"
  RENOVATE_REPOSITORIES="$origin_path"
fi
nix run nixpkgs#renovate -- \
  --platform github \
  --token "$RENOVATE_TOKEN" \
  "$RENOVATE_REPOSITORIES" \
  "$@"
