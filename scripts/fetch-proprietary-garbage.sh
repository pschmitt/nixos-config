#!/usr/bin/env bash

set -euo pipefail

# List of packages that have a 'proprietarySource' attribute
PROPRIETARY_PACKAGES=(
  "falcon-sensor-wiit"
  "ComicCode"
  "MonoLisa"
  "MonoLisa-Custom"
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--username USER] [--password PASS] [--auth USER:PASS]

Environment variables:
  BLOBS_BASIC_AUTH  Provide HTTP basic auth credentials directly (USER:PASS)
  BLOBS_USERNAME    Username part of the credentials
  BLOBS_PASSWORD    Password part of the credentials
USAGE
}

fetch_package_source() {
  local pkg="$1"
  local json

  echo "Checking $pkg..."

  # Evaluate the proprietarySource attribute
  # Gotta use --impure and NIXPKGS_ALLOW_UNFREE=1 here!
  if ! json=$(NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure \
    ".#packages.x86_64-linux.$pkg.proprietarySource")
  then
    echo "  Failed to evaluate proprietarySource for $pkg (or it doesn't exist)"
    return 1
  fi

  local name url sha256
  IFS=$'\t' read -r name url sha256 <<< "$(jq -er <<< "$json" '
    [.name, .url, .sha256] | @tsv
  ')"

  if [[ "$name" == "null" || "$url" == "null" || "$sha256" == "null" ]]
  then
    echo "  Invalid proprietarySource metadata for $pkg"
    return 1
  fi

  # Simple check: if we don't have credentials, we can't download.
  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
     # If we can't download, we hope it's already there.
     # We can't easily verify without the file content or complex nix queries.
     echo "  ⚠️  BLOBS_BASIC_AUTH not set, skipping download check for $name"
     return 0
  fi

  echo "  Downloading $name from $url..."

  local tmp_file
  tmp_file="$(mktemp "${name}.XXXXXX")"

  local -a curl_args=(
    --fail
    --location
    --retry 5
    --retry-delay 2
    --silent
    --show-error
    --user "$BLOBS_BASIC_AUTH"
  )

  if ! curl "${curl_args[@]}" "$url" --output "$tmp_file"
  then
    echo "  ❌ Failed to download $url"
    rm -f "$tmp_file"
    return 1
  fi

  echo "  Adding to Nix store..."
  if ! nix-store --add-fixed sha256 "$tmp_file"
  then
    echo "  ❌ Failed to add to Nix store"
    rm -f "$tmp_file"
    return 1
  fi

  rm -f "$tmp_file"
  echo "  ✅ Successfully added $name"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  BLOBS_USERNAME=${BLOBS_USERNAME:-}
  BLOBS_PASSWORD=${BLOBS_PASSWORD:-}
  BLOBS_AUTH=${BLOBS_AUTH:-}

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --username)
        BLOBS_USERNAME="$2"
        shift 2
        ;;
      --password)
        BLOBS_PASSWORD="$2"
        shift 2
        ;;
      --auth)
        BLOBS_AUTH="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    if [[ -n "$BLOBS_AUTH" ]]
    then
      BLOBS_BASIC_AUTH="$BLOBS_AUTH"
    elif [[ -n "$BLOBS_USERNAME" || -n "$BLOBS_PASSWORD" ]]
    then
      if [[ -z "$BLOBS_USERNAME" || -z "$BLOBS_PASSWORD" ]]
      then
        echo "--username and --password must be provided together" >&2
        exit 64
      fi

      BLOBS_BASIC_AUTH="${BLOBS_USERNAME}:${BLOBS_PASSWORD}"
    fi
  fi

  for PKG in "${PROPRIETARY_PACKAGES[@]}"
  do
    fetch_package_source "$PKG"
  done
fi
