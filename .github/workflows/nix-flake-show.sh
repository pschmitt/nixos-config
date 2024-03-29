#!/usr/bin/env bash

mapfile -t PKGS < <(nix flake show --json | \
  jq -er '.packages["x86_64-linux"] | keys[]')

PKGS_FREE=()
PKGS_NONFREE=()
for p in "${PKGS[@]}"
do
  # Skip proprietary packages
  if nix eval --impure --json ".#${p}.meta.license" | jq -er '.free'
  then
    PKGS_FREE+=("$p")
  else
    PKGS_NONFREE+=("$p")
  fi
done

JSON_PKGS=$(printf '%s\n' "${PKGS[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_FREE=$(printf '%s\n' "${PKGS_FREE[@]}" | jq -Rcn '[inputs]')
JSON_PKGS_NONFREE=$(printf '%s\n' "${PKGS_NONFREE[@]}" | jq -Rcn '[inputs]')
JSON_NIXOS_CONFIGS=$(nix flake show --json | jq -c '.nixosConfigurations | keys')

jq -cn \
  --argjson hosts "$JSON_NIXOS_CONFIGS" \
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
    hosts: $hosts
  }
'
