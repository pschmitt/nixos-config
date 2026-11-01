#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--pkg NAME --system SYSTEM | --host NAME | --droid NAME] [--copy] [OPTIONS]

Targets:
  --pkg NAME            Build or copy a package
  --host NAME           Build or copy a host configuration
  --droid NAME          Build or copy a nix-on-droid configuration

Package options:
  --system SYSTEM       Nix system for the package
  --nonfree             Treat the package as nonfree
  --oci                 Treat the package as OCI-specific

General options:
  --copy                Push the target(s) to niks3 (\$NIKS3_SERVER_URL) instead of building
  -h, --help            Show this help
EOF
}

require_command() {
  local cmd="$1"

  if ! command -v "$cmd" >/dev/null 2>&1
  then
    echo "Missing required command: $cmd" >&2
    return 1
  fi
}

package_ref() {
  local pkg="$1"
  local system="$2"

  printf '.#packages.%s.%s\n' "$system" "$pkg"
}

host_ref() {
  local host="$1"

  printf '.#nixosConfigurations.%s.config.system.build.toplevel\n' "$host"
}

droid_ref() {
  local droid="$1"

  printf '.#nixOnDroidConfigurations.%s.activationPackage\n' "$droid"
}

host_system() {
  local host="$1"

  nix eval --raw ".#nixosConfigurations.${host}.config.nixpkgs.system"
}

droid_system() {
  local droid="$1"

  nix eval --impure --raw ".#nixOnDroidConfigurations.${droid}.pkgs.stdenv.hostPlatform.system"
}

show_result_tree() {
  if [[ -e result ]] && command -v tree >/dev/null 2>&1
  then
    tree result
  fi
}

# Every CI build runs on a runner of its target architecture.
require_native_system() {
  local system="$1"

  if [[ "$system" != "$(uname -m)-linux" ]]
  then
    printf 'Use a native runner for %s\n' "$system" >&2
    return 2
  fi
}

# The niks3 client of the server's release (nixos-config-private's niks3
# input); the upstream cache supplies it.
NIKS3_CLI="github:Mic92/niks3/a79dc58832332ebd953974e71160ab69e2371d62#niks3"

# Push a target's outputs to niks3 with a GitHub OIDC token. main pins them
# (gh-main-<target>-<output index>); pull requests push unpinned, so niks3's
# GC collects them.
publish_ref() {
  local ref="$1"
  local paths_json="$2"
  local cli helper path pin index
  local -a auth

  if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]
  then
    printf 'No GitHub OIDC token available (fork PR?); not publishing %s\n' "$ref" >&2
    return 0
  fi
  cli="$(nix build --no-link --print-out-paths "$NIKS3_CLI")"
  helper="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/niks3-oidc-token.py"
  auth=(--server-url "$NIKS3_SERVER_URL" --auth-token-script "python3 $helper")
  index=0
  while read -r path
  do
    pin="gh-main-${ref#*#}-${index}"
    if [[ "$NIX_CACHE_SCOPE" != main ]]
    then
      "$cli/bin/niks3" push "${auth[@]}" "$path"
    else
      "$cli/bin/niks3" push "${auth[@]}" --pin "$pin" "$path"
    fi
    index=$((index + 1))
  done < <(jq -r '.[]' <<< "$paths_json")
}

build_ref() {
  local ref="$1"
  local impure="${2:-}"
  local -a cmd=(nix build --print-build-logs)

  if [[ -n "$impure" ]]
  then
    cmd+=(--impure)
  fi

  cmd+=("$ref")
  "${cmd[@]}"
}

copy_refs() {
  local impure="${1:-}"
  shift
  local -a refs=("$@")
  local -a paths_query=(nix path-info)
  local ref paths paths_json

  if [[ ${#refs[@]} -eq 0 || -z "${NIKS3_SERVER_URL:-}" || -z "${NIX_CACHE_SCOPE:-}" ]]
  then
    printf 'Copy requires refs, NIKS3_SERVER_URL and NIX_CACHE_SCOPE\n' >&2
    return 2
  fi

  if [[ -n "$impure" ]]
  then
    paths_query+=(--impure)
  fi

  for ref in "${refs[@]}"
  do
    paths="$("${paths_query[@]}" "$ref")"
    paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' <<< "$paths")"
    publish_ref "$ref" "$paths_json"
  done
}

build_package() {
  local pkg="$1"
  local system="$2"
  local nonfree="${3:-}"

  require_native_system "$system" || return $?

  build_ref "$(package_ref "$pkg" "$system")" "$nonfree"

  show_result_tree
}

copy_package() {
  local pkg="$1"
  local system="$2"
  local nonfree="${3:-}"

  copy_refs "$nonfree" "$(package_ref "$pkg" "$system")"
}

build_host() {
  local host="$1"
  local system

  system="$(host_system "$host")"
  require_native_system "$system" || return $?

  build_ref "$(host_ref "$host")" ""
}

copy_host() {
  local host="$1"

  copy_refs "" "$(host_ref "$host")"
}

build_droid() {
  local droid="$1"
  local system

  system="$(droid_system "$droid")"
  require_native_system "$system" || return $?

  build_ref "$(droid_ref "$droid")" 1
}

copy_droid() {
  local droid="$1"

  copy_refs 1 "$(droid_ref "$droid")"
}

main() {
  local copy
  local nonfree
  local oci
  local pkg=""
  local host=""
  local droid=""
  local system=""

  copy=
  nonfree=
  oci=

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      --pkg)
        pkg="${2:-}"
        shift 2
        ;;
      --host)
        host="${2:-}"
        shift 2
        ;;
      --droid)
        droid="${2:-}"
        shift 2
        ;;
      --system)
        system="${2:-}"
        shift 2
        ;;
      --copy)
        copy=1
        shift
        ;;
      --nonfree)
        nonfree=1
        shift
        ;;
      --oci)
        oci=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  require_command nix

  if [[ -n "$pkg" && ( -n "$host" || -n "$droid" ) ]]
  then
    echo "Choose exactly one of --pkg, --host or --droid" >&2
    return 2
  fi

  if [[ -z "$pkg" && -z "$host" && -z "$droid" ]]
  then
    echo "Missing --pkg, --host or --droid" >&2
    usage >&2
    return 2
  fi

  if [[ -n "$pkg" ]]
  then
    if [[ -z "$system" ]]
    then
      echo "--system is required with --pkg" >&2
      return 2
    fi

    if [[ -n "$copy" ]]
    then
      copy_package "$pkg" "$system" "$nonfree"
    else
      build_package "$pkg" "$system" "$nonfree"
    fi

    return 0
  fi

  if [[ -n "$system" || -n "$nonfree" || -n "$oci" ]]
  then
    echo "--system, --nonfree and --oci are only valid with --pkg" >&2
    return 2
  fi

  if [[ -n "$host" ]]
  then
    if [[ -n "$copy" ]]
    then
      copy_host "$host"
    else
      build_host "$host"
    fi

    return 0
  fi

  if [[ -n "$copy" ]]
  then
    copy_droid "$droid"
  else
    build_droid "$droid"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ts=2 sw=2 et:
