#!/usr/bin/env bash

NIX_FLAKE_SHOW=$(nix flake show --json)
mapfile -t PKGS < <(jq -er '.packages["x86_64-linux"] | keys[]' <<< "$NIX_FLAKE_SHOW")

PKGS_FREE=()
PKGS_NONFREE=()
for p in "${PKGS[@]}"
do
  # Skip proprietary packages
  if nix eval --impure --json ".#${p}.meta.license" | jq -er '.free' >/dev/null
  then
    PKGS_FREE+=("$p")
  else
    PKGS_NONFREE+=("$p")
  fi
done

JSON_PKGS=$(printf '%s\n' "${PKGS[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_FREE=$(printf '%s\n' "${PKGS_FREE[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_NONFREE=$(printf '%s\n' "${PKGS_NONFREE[@]}" | jq -Rcn '[inputs]')
# FIXME We should determine the target architecture by evaluating the flake and
# not hardcode it based on the hostname
JSON_NIXOS_CONFIGS_X86_64=$(jq -c '[.nixosConfigurations | keys[] | select(. | test("^oci-") | not)]' <<< "$NIX_FLAKE_SHOW")
JSON_NIXOS_CONFIGS_AARCH64=$(jq -c '[.nixosConfigurations | keys[] | select(. | test("^oci-"))]' <<< "$NIX_FLAKE_SHOW")

jq -cn \
  --argjson hosts_x86_64 "$JSON_NIXOS_CONFIGS_X86_64" \
  --argjson hosts_aarch64 "$JSON_NIXOS_CONFIGS_AARCH64" \
  --argjson pkgs "$JSON_PKGS" \
  --argjson pkgs_nonfree "$JSON_PKGS_NONFREE" \
  --argjson pkgs_free "$JSON_PKGS_FREE" \
'
  {
    pkgs: {
      free: $pkgs_free,
      nonfree: $pkgs_nonfree,
      all: $pkgs
    },
    hosts: {
      x86_64: $hosts_x86_64,
      aarch64: $hosts_aarch64
    }
  }
'
