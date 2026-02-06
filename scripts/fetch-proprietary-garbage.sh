#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--username USER] [--password PASS] [--auth USER:PASS]

Environment variables:
  BLOBS_BASIC_AUTH  Provide HTTP basic auth credentials directly (USER:PASS)
  BLOBS_USERNAME    Username part of the credentials
  BLOBS_PASSWORD    Password part of the credentials
USAGE
}

# List of packages that have a 'proprietarySource' attribute
get_proprietary_packages() {
  # shellcheck disable=SC2016
  NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure --expr '
    let
      flake = builtins.getFlake (builtins.toString ./.);
      pkgs = flake.packages.x86_64-linux;
      hasProprietarySource = n:
        let res = builtins.tryEval (pkgs.${n}.proprietarySource or null);
        in res.success && res.value != null;
      proprietaryPkgs = builtins.filter hasProprietarySource (builtins.attrNames pkgs);
    in
      proprietaryPkgs
  ' | jq -r '.[]'
}

fetch_package_source() {
  local pkg="$1"
  local json

  echo "Processing $pkg"

  # Evaluate the proprietarySource attribute
  # Gotta use --impure and NIXPKGS_ALLOW_UNFREE=1 here!
  if ! json=$(NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure \
    ".#packages.x86_64-linux.$pkg.proprietarySource")
  then
    echo "Failed to evaluate proprietarySource for $pkg (or it doesn't exist)"
    return 1
  fi

  local name url sha256
  IFS=$'\t' read -r name url sha256 <<< "$(jq -er <<< "$json" '
    [.name, .url, .sha256] | @tsv
  ')"

  if [[ "$name" == "null" || "$url" == "null" || "$sha256" == "null" ]]
  then
    echo "Invalid proprietarySource metadata for $pkg"
    return 1
  fi

  # Simple check: if we don't have credentials, we might not be able to download.
  if [[ -z "${BLOBS_BASIC_AUTH:-}" ]]
  then
    echo "⚠️ BLOBS_BASIC_AUTH not set, download might fail for $name"
  fi

  echo "Downloading $name from $url"

  local tmp_dir tmp_file
  tmp_dir="$(mktemp -d)"
  tmp_file="${tmp_dir}/${name}"

  local -a curl_args=(
    --fail
    --location
    --retry 5
    --retry-delay 2
    --silent
    --show-error
    --user "${BLOBS_BASIC_AUTH:-:}"
  )

  if ! curl "${curl_args[@]}" "$url" --output "$tmp_file"
  then
    echo "❌ Failed to download $url"
    rm -rf "$tmp_dir"
    return 1
  fi

  local actual_hash_sri
  actual_hash_sri="$(nix hash file --type sha256 "$tmp_file")"

  echo "nix hash of our downloaded file (${tmp_file}):"
  echo "$actual_hash_sri"

  if [[ "$sha256" == sha256-* ]]
  then
    if [[ "$actual_hash_sri" != "$sha256" ]]
    then
      echo "❌ Hash mismatch for $name"
      echo "Expected: $sha256"
      echo "Actual:   $actual_hash_sri"
      rm -rf "$tmp_dir"
      return 1
    fi
  else
    echo "⚠️ Expected hash is not SRI form (sha256-...), skipping hash verification for $name"
  fi

  echo "Adding $tmp_file to Nix store"
  if ! nix-store --add-fixed sha256 "$tmp_file"
  then
    echo "❌ Failed to add to Nix store"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  echo "✅ Successfully added $name"
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

  echo "Discovering proprietary packages"
  mapfile -t PROPRIETARY_PACKAGES < <(get_proprietary_packages)

  if [[ ${#PROPRIETARY_PACKAGES[@]} -eq 0 ]]
  then
    echo "No proprietary packages found."
    exit 0
  fi

  for PKG in "${PROPRIETARY_PACKAGES[@]}"
  do
    fetch_package_source "$PKG"
  done
fi
