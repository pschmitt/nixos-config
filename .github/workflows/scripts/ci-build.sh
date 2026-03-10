#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--pkg NAME --system SYSTEM | --host NAME] [--copy] [OPTIONS]

Targets:
  --pkg NAME            Build or copy a package
  --host NAME           Build or copy a host configuration

Package options:
  --system SYSTEM       Nix system for the package
  --nonfree             Treat the package as nonfree
  --oci                 Treat the package as OCI-specific

General options:
  --copy                Copy the target(s) to \$NIX_DEST_STORE_URL instead of building
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

host_system() {
  local host="$1"

  nix eval --raw ".#nixosConfigurations.${host}.config.nixpkgs.system"
}

show_result_tree() {
  if [[ -e result ]] && command -v tree >/dev/null 2>&1
  then
    tree result
  fi
}

should_use_builders() {
  local system="$1"
  local nonfree="${2:-}"
  local oci="${3:-}"

  if [[ -n "$nonfree" || -n "$oci" || "$system" == "aarch64-linux" ]]
  then
    return 0
  fi

  return 1
}

build_ref() {
  local ref="$1"
  local use_builders="${2:-}"
  local impure="${3:-}"
  local -a cmd=(nix build --print-build-logs)

  if [[ -n "$use_builders" ]]
  then
    cmd+=(--builders "$NIX_BUILDER")
  fi

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
  local key_file
  local -a path_info_cmd=(nix path-info --recursive)
  local -a copy_cmd=(nix copy --to "$NIX_DEST_STORE_URL")

  if [[ ${#refs[@]} -eq 0 ]]
  then
    echo "No refs to copy" >&2
    return 1
  fi

  if [[ -z "${NIX_DEST_STORE_URL:-}" ]]
  then
    echo "NIX_DEST_STORE_URL is required for --copy" >&2
    return 1
  fi

  if [[ -z "${NIX_STORE_PRIVKEY:-}" ]]
  then
    echo "NIX_STORE_PRIVKEY is required for --copy" >&2
    return 1
  fi

  if [[ -n "$impure" ]]
  then
    path_info_cmd+=(--impure)
    copy_cmd+=(--impure)
  fi

  key_file="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$key_file'" RETURN

  umask 077
  printf '%s' "$NIX_STORE_PRIVKEY" > "$key_file"
  "${path_info_cmd[@]}" "${refs[@]}" | \
    nix store sign --key-file "$key_file" --stdin
  "${copy_cmd[@]}" "${refs[@]}"
}

build_package() {
  local pkg="$1"
  local system="$2"
  local nonfree="${3:-}"
  local oci="${4:-}"

  if should_use_builders "$system" "$nonfree" "$oci"
  then
    build_ref "$(package_ref "$pkg" "$system")" 1 "$nonfree"
  else
    build_ref "$(package_ref "$pkg" "$system")" "" ""
  fi

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
  local use_builders

  system="$(host_system "$host")"
  use_builders=
  if [[ "$system" == "aarch64-linux" ]]
  then
    use_builders=1
  fi

  build_ref "$(host_ref "$host")" "$use_builders" ""
}

copy_host() {
  local host="$1"

  copy_refs "" "$(host_ref "$host")"
}

main() {
  local copy
  local nonfree
  local oci
  local pkg=""
  local host=""
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

  if [[ -n "$pkg" && -n "$host" ]]
  then
    echo "Choose either --pkg or --host" >&2
    return 2
  fi

  if [[ -z "$pkg" && -z "$host" ]]
  then
    echo "Missing --pkg or --host" >&2
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
      build_package "$pkg" "$system" "$nonfree" "$oci"
    fi

    return 0
  fi

  if [[ -n "$system" || -n "$nonfree" || -n "$oci" ]]
  then
    echo "--system, --nonfree and --oci are only valid with --pkg" >&2
    return 2
  fi

  if [[ -n "$copy" ]]
  then
    copy_host "$host"
  else
    build_host "$host"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ts=2 sw=2 et:
