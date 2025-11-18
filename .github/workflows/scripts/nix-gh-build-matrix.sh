#!/usr/bin/env bash

set -euo pipefail

export NIX_CONFIG="accept-flake-config = true${NIX_CONFIG:+ $NIX_CONFIG}"

nix_host_architecture() {
  local host="$1"
  nix eval --raw ".#nixosConfigurations.${host}.config.nixpkgs.system"
}

NIX_FLAKE_SHOW=$(nix flake show --json)
mapfile -t PKGS < <(jq -er '.packages["x86_64-linux"] | keys[]' <<< "$NIX_FLAKE_SHOW")

PKGS_FREE=()
PKGS_NONFREE=()
PKGS_OCI=()
for p in "${PKGS[@]}"
do
  # Special snowflakes
  case "$p" in
    oracle-cloud-agent)
      # Oracle Cloud Agent's RPM can only be fetched from OCI servers
      PKGS_OCI+=("$p")
      continue
      ;;
  esac

  # Skip proprietary packages
  if nix eval --impure --json ".#${p}.meta.license" | jq -er '.free' >/dev/null
  then
    PKGS_FREE+=("$p")
  else
    PKGS_NONFREE+=("$p")
  fi
done

for h in $(jq -r '.nixosConfigurations | keys[]' <<< "$NIX_FLAKE_SHOW")
do
  case "$(nix_host_architecture "$h")" in
    x86_64-linux)
      JSON_NIXOS_CONFIGS_X86_64=$(jq -cn \
        --argjson arr "${JSON_NIXOS_CONFIGS_X86_64:-[]}" \
        --arg h "$h" \
        '$arr + [$h]')
      ;;
    aarch64-linux)
      JSON_NIXOS_CONFIGS_AARCH64=$(jq -cn \
        --argjson arr "${JSON_NIXOS_CONFIGS_AARCH64:-[]}" \
        --arg h "$h" \
        '$arr + [$h]')
      ;;
  esac
done


JSON_PKGS=$(printf '%s\n' "${PKGS[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_FREE=$(printf '%s\n' "${PKGS_FREE[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_NONFREE=$(printf '%s\n' "${PKGS_NONFREE[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_OCI=$(printf '%s\n' "${PKGS_OCI[@]}" | jq -Rcn '[inputs]')

jq -cn \
  --argjson hosts_x86_64 "$JSON_NIXOS_CONFIGS_X86_64" \
  --argjson hosts_aarch64 "$JSON_NIXOS_CONFIGS_AARCH64" \
  --argjson pkgs "$JSON_PKGS" \
  --argjson pkgs_nonfree "$JSON_PKGS_NONFREE" \
  --argjson pkgs_free "$JSON_PKGS_FREE" \
  --argjson pkgs_oci "$JSON_PKGS_OCI" \
'
  {
    pkgs: {
      free: $pkgs_free,
      nonfree: $pkgs_nonfree,
      oci: $pkgs_oci,
      all: $pkgs
    },
    hosts: {
      amd64: $hosts_x86_64,
      aarch64: $hosts_aarch64
    }
  }
'
