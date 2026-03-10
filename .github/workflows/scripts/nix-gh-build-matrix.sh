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

list_package_names() {
  local system="$1"

  nix eval --impure --json ".#packages.${system}" --apply 'pkgs: builtins.attrNames pkgs'
}

list_package_metadata() {
  local system="$1"

  # shellcheck disable=SC2016
  nix eval --impure --json ".#packages.${system}" --apply '
    pkgs:
      let
        isFree = license:
          if builtins.isList license then
            builtins.any isFree license
          else if builtins.isAttrs license && license ? free then
            license.free
          else
            false;
        supportsSystem = pkg:
          let
            platforms =
              if pkg ? meta && pkg.meta ? platforms then
                pkg.meta.platforms
              else
                null;
            badPlatforms =
              if pkg ? meta && pkg.meta ? badPlatforms then
                pkg.meta.badPlatforms
              else
                [ ];
            inPlatforms =
              if platforms == null then
                true
              else if builtins.isList platforms then
                builtins.elem "'"$system"'" platforms
              else
                false;
            inBadPlatforms =
              if builtins.isList badPlatforms then
                builtins.elem "'"$system"'" badPlatforms
              else
                false;
          in
            inPlatforms && (!inBadPlatforms);
      in
        builtins.map
          (name: {
            inherit name;
            free =
              if pkgs.${name} ? meta && pkgs.${name}.meta ? license then
                isFree pkgs.${name}.meta.license
              else
                false;
            supported = supportsSystem pkgs.${name};
          })
          (builtins.attrNames pkgs)
  '
}

json_array_from_values() {
  if (( $# == 0 ))
  then
    printf '%s\n' '[]'
    return 0
  fi

  printf '%s\0' "$@" | jq -Rs 'split("\u0000")[:-1]'
}

categorize_packages() {
  local metadata_json="$1"
  local out_prefix="$2"

  local -n out_all="${out_prefix}_all"
  local -n out_free="${out_prefix}_free"
  local -n out_nonfree="${out_prefix}_nonfree"
  local -n out_oci="${out_prefix}_oci"
  local name

  mapfile -t out_all < <(jq -er '.[] | select(.supported == true) | .name' <<< "$metadata_json")
  out_free=()
  out_nonfree=()
  out_oci=()

  for name in "${out_all[@]}"
  do
    case "$name" in
      oracle-cloud-agent)
        out_oci+=("$name")
        ;;
      *)
        if jq -e --arg pkg "$name" '.[] | select(.name == $pkg and .free == true)' <<< "$metadata_json" >/dev/null
        then
          out_free+=("$name")
        else
          out_nonfree+=("$name")
        fi
        ;;
    esac
  done
}

PACKAGE_METADATA_X86_64_JSON="$(list_package_metadata x86_64-linux)"
if ! jq -e 'type == "array"' <<< "$PACKAGE_METADATA_X86_64_JSON" >/dev/null
then
  echo "Failed to list x86_64-linux package metadata" >&2
  exit 1
fi

PACKAGE_METADATA_AARCH64_JSON="$(list_package_metadata aarch64-linux)"
if ! jq -e 'type == "array"' <<< "$PACKAGE_METADATA_AARCH64_JSON" >/dev/null
then
  echo "Failed to list aarch64-linux package metadata" >&2
  exit 1
fi

PKGS_X86_64_all=()
PKGS_X86_64_free=()
PKGS_X86_64_nonfree=()
PKGS_X86_64_oci=()
PKGS_AARCH64_all=()
PKGS_AARCH64_free=()
PKGS_AARCH64_nonfree=()
PKGS_AARCH64_oci=()

categorize_packages "$PACKAGE_METADATA_X86_64_JSON" "PKGS_X86_64"
categorize_packages "$PACKAGE_METADATA_AARCH64_JSON" "PKGS_AARCH64"

NIXOS_CONFIGS_JSON="$(list_nixos_configurations)"
if ! jq -e 'type == "array"' <<< "$NIXOS_CONFIGS_JSON" >/dev/null
then
  echo "Failed to list nixosConfigurations" >&2
  exit 1
fi

mapfile -t NIXOS_CONFIGS < <(jq -er '.[]' <<< "$NIXOS_CONFIGS_JSON")
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


JSON_PKGS_X86_64_ALL="$(json_array_from_values "${PKGS_X86_64_all[@]}")"
JSON_PKGS_X86_64_FREE="$(json_array_from_values "${PKGS_X86_64_free[@]}")"
JSON_PKGS_X86_64_NONFREE="$(json_array_from_values "${PKGS_X86_64_nonfree[@]}")"
JSON_PKGS_X86_64_OCI="$(json_array_from_values "${PKGS_X86_64_oci[@]}")"
JSON_PKGS_AARCH64_ALL="$(json_array_from_values "${PKGS_AARCH64_all[@]}")"
JSON_PKGS_AARCH64_FREE="$(json_array_from_values "${PKGS_AARCH64_free[@]}")"
JSON_PKGS_AARCH64_NONFREE="$(json_array_from_values "${PKGS_AARCH64_nonfree[@]}")"
JSON_PKGS_AARCH64_OCI="$(json_array_from_values "${PKGS_AARCH64_oci[@]}")"
JSON_PKGS_ALL="$(jq -cn \
  --argjson x86 "$JSON_PKGS_X86_64_ALL" \
  --argjson arm "$JSON_PKGS_AARCH64_ALL" \
  '([ $x86[] | { name: ., systems: ["x86_64-linux"] } ] +
    [ $arm[] | { name: ., systems: ["aarch64-linux"] } ])
    | group_by(.name)
    | map({
        name: .[0].name,
        systems: (map(.systems[]) | unique)
      })')"
JSON_PKGS_FREE="$(jq -cn \
  --argjson x86 "$JSON_PKGS_X86_64_FREE" \
  --argjson arm "$JSON_PKGS_AARCH64_FREE" \
  '([ $x86[] | { name: ., systems: ["x86_64-linux"] } ] +
    [ $arm[] | { name: ., systems: ["aarch64-linux"] } ])
    | group_by(.name)
    | map({
        name: .[0].name,
        systems: (map(.systems[]) | unique)
      })')"
JSON_PKGS_NONFREE="$(jq -cn \
  --argjson x86 "$JSON_PKGS_X86_64_NONFREE" \
  --argjson arm "$JSON_PKGS_AARCH64_NONFREE" \
  '([ $x86[] | { name: ., systems: ["x86_64-linux"] } ] +
    [ $arm[] | { name: ., systems: ["aarch64-linux"] } ])
    | group_by(.name)
    | map({
        name: .[0].name,
        systems: (map(.systems[]) | unique)
      })')"
JSON_PKGS_OCI="$(jq -cn \
  --argjson x86 "$JSON_PKGS_X86_64_OCI" \
  --argjson arm "$JSON_PKGS_AARCH64_OCI" \
  '([ $x86[] | { name: ., systems: ["x86_64-linux"] } ] +
    [ $arm[] | { name: ., systems: ["aarch64-linux"] } ])
    | group_by(.name)
    | map({
        name: .[0].name,
        systems: (map(.systems[]) | unique)
      })')"

jq -cn \
  --argjson hosts_x86_64 "$JSON_NIXOS_CONFIGS_X86_64" \
  --argjson hosts_aarch64 "$JSON_NIXOS_CONFIGS_AARCH64" \
  --argjson pkgs_all "$JSON_PKGS_ALL" \
  --argjson pkgs_free "$JSON_PKGS_FREE" \
  --argjson pkgs_nonfree "$JSON_PKGS_NONFREE" \
  --argjson pkgs_oci "$JSON_PKGS_OCI" \
  --argjson pkgs_x86_64_all "$JSON_PKGS_X86_64_ALL" \
  --argjson pkgs_x86_64_free "$JSON_PKGS_X86_64_FREE" \
  --argjson pkgs_x86_64_nonfree "$JSON_PKGS_X86_64_NONFREE" \
  --argjson pkgs_x86_64_oci "$JSON_PKGS_X86_64_OCI" \
  --argjson pkgs_aarch64_all "$JSON_PKGS_AARCH64_ALL" \
  --argjson pkgs_aarch64_free "$JSON_PKGS_AARCH64_FREE" \
  --argjson pkgs_aarch64_nonfree "$JSON_PKGS_AARCH64_NONFREE" \
  --argjson pkgs_aarch64_oci "$JSON_PKGS_AARCH64_OCI" \
'
  {
    pkgs: {
      all: $pkgs_all,
      free: $pkgs_free,
      nonfree: $pkgs_nonfree,
      oci: $pkgs_oci
    },
    pkgs_by_system: {
      x86_64: {
        all: $pkgs_x86_64_all,
        free: $pkgs_x86_64_free,
        nonfree: $pkgs_x86_64_nonfree,
        oci: $pkgs_x86_64_oci
      },
      aarch64: {
        all: $pkgs_aarch64_all,
        free: $pkgs_aarch64_free,
        nonfree: $pkgs_aarch64_nonfree,
        oci: $pkgs_aarch64_oci
      }
    },
    hosts: {
      amd64: $hosts_x86_64,
      aarch64: $hosts_aarch64
    }
  }
'
