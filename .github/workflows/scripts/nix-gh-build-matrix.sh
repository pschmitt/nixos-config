#!/usr/bin/env bash

set -euo pipefail

export NIX_CONFIG="accept-flake-config = true${NIX_CONFIG:+ $NIX_CONFIG}"

JSON_NIXOS_CONFIGS_X86_64='[]'
JSON_NIXOS_CONFIGS_AARCH64='[]'

nix_host_architecture() {
  local host="$1"
  nix eval --raw ".#nixosConfigurations.${host}.config.nixpkgs.system"
}

list_nixos_configurations() {
  nix eval --json '.#nixosConfigurations' --apply 'configs: builtins.attrNames configs'
}

list_x86_64_packages() {
  # shellcheck disable=SC2016
  nix eval --impure --json '.#packages.x86_64-linux' --apply '
    pkgs:
      let
        isFree = license:
          if builtins.isList license then
            builtins.any isFree license
          else if builtins.isAttrs license && license ? free then
            license.free
          else
            false;
      in
        builtins.map
          (name: {
            inherit name;
            free =
              if pkgs.${name} ? meta && pkgs.${name}.meta ? license then
                isFree pkgs.${name}.meta.license
              else
                false;
          })
          (builtins.attrNames pkgs)
  '
}

NIX_FLAKE_SHOW=$(nix flake show --json)
mapfile -t PKGS < <(jq -er '.packages["x86_64-linux"] | keys[]' <<< "$NIX_FLAKE_SHOW")
PACKAGE_METADATA_JSON="$(list_x86_64_packages)"

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
  if jq -e --arg pkg "$p" '.[] | select(.name == $pkg and .free == true)' <<< "$PACKAGE_METADATA_JSON" >/dev/null
  then
    PKGS_FREE+=("$p")
  else
    PKGS_NONFREE+=("$p")
  fi
done

mapfile -t NIXOS_CONFIGS < <(list_nixos_configurations | jq -er '.[]')
for h in "${NIXOS_CONFIGS[@]}"
do
  case "$(nix_host_architecture "$h")" in
    x86_64-linux)
      JSON_NIXOS_CONFIGS_X86_64=$(jq -cn \
        --argjson arr "$JSON_NIXOS_CONFIGS_X86_64" \
        --arg h "$h" \
        '$arr + [$h]')
      ;;
    aarch64-linux)
      JSON_NIXOS_CONFIGS_AARCH64=$(jq -cn \
        --argjson arr "$JSON_NIXOS_CONFIGS_AARCH64" \
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
