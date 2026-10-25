#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [--pkg NAME --system SYSTEM | --host NAME | --home NAME | --droid NAME] [--copy] [OPTIONS]

Targets:
  --pkg NAME            Build or copy a package
  --host NAME           Build or copy a host configuration
  --home NAME           Build or copy a standalone Home Manager configuration
  --droid NAME          Build or copy a nix-on-droid configuration

Package options:
  --system SYSTEM       Nix system for the package
  --nonfree             Treat the package as nonfree
  --oci                 Treat the package as OCI-specific

General options:
  --copy                Copy the target(s) to \$NIX_DEST_STORE_URL instead of building
  --check-cache         Retain an existing remote output; return 1 on a cache miss
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

home_ref() {
  local home="$1"

  printf '.#homeConfigurations.%s.activationPackage\n' "$home"
}

droid_ref() {
  local droid="$1"

  printf '.#nixOnDroidConfigurations.%s.activationPackage\n' "$droid"
}

host_system() {
  local host="$1"

  nix eval --raw ".#nixosConfigurations.${host}.config.nixpkgs.system"
}

home_system() {
  local home="$1"

  nix eval --raw ".#homeConfigurations.${home}.pkgs.stdenv.hostPlatform.system"
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

resolve_output_paths() {
  local ref="$1"
  local impure="${2:-}"
  local -a cmd=(nix eval --json)
  if [[ -n "$impure" ]]
  then
    cmd+=(--impure)
  fi
  # shellcheck disable=SC2016 # This interpolation belongs to Nix.
  "${cmd[@]}" "$ref" --apply 'drv: builtins.map (name: drv.${name}.outPath) drv.outputs'
}

cached_output_paths() {
  local ref="$1"
  local impure="${2:-}"
  local paths_json paths_text
  local -a paths
  [[ -n "${NIX_DEST_STORE_URL:-}" && -n "${NIX_CACHE_PUBLISH_HOST:-}" && -n "${NIX_CACHE_SCOPE:-}" ]] || return 1
  paths_json="$(resolve_output_paths "$ref" "$impure")" || return 1
  paths_text="$(jq -er '.[]' <<< "$paths_json")" || return 1
  readarray -t paths <<< "$paths_text"
  nix path-info --store "$NIX_DEST_STORE_URL" "${paths[@]}" >/dev/null 2>&1 || return 1
  printf '%s\n' "$paths_json"
}

retain_ref() {
  local ref="$1"
  local paths_json="$2"
  local revision timestamp
  revision="$(git rev-parse HEAD)"
  timestamp="$(git show -s --format=%ct HEAD)"
  jq -cn --arg target "${ref#*#}" --arg scope "$NIX_CACHE_SCOPE" \
    --arg revision "$revision" --argjson timestamp "$timestamp" --argjson paths "$paths_json" \
    '{target: $target, scope: $scope, revision: $revision, timestamp: $timestamp, paths: $paths}' | \
    ssh "$NIX_CACHE_PUBLISH_HOST" /run/current-system/sw/bin/nix-cache-retain publish
}

publish_s3_ref() {
  local ref="$1"
  local paths_json="$2"
  local paths_text
  local -a paths
  paths_text="$(jq -er '.[]' <<< "$paths_json")" || return
  readarray -t paths <<< "$paths_text"
  bash "$(dirname -- "${BASH_SOURCE[0]}")/ci-push-cache.sh" "${ref#*#}" "${paths[@]}"
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

  local cached
  if cached="$(cached_output_paths "$ref" "$impure" 2>/dev/null)"
  then
    # Pin the remote hit now, before a later CI step or GC can race us.
    retain_ref "$ref" "$cached" || return
    printf 'Already cached and retained: %s\n' "$ref"
    return 0
  fi

  cmd+=("$ref")
  "${cmd[@]}"
}

copy_refs() {
  local impure="${1:-}"
  shift
  local -a refs=("$@")
  local -a path_info_cmd=(nix path-info --recursive)
  local -a copy_cmd=()
  local -a paths_query=(nix path-info)
  local ref paths paths_json cached key_file closure_json

  if [[ ${#refs[@]} -eq 0 || -z "${NIX_DEST_STORE_URL:-}" || -z "${NIX_CACHE_PUBLISH_HOST:-}" || -z "${NIX_CACHE_SCOPE:-}" ]]
  then
    printf 'Copy requires refs, NIX_DEST_STORE_URL, NIX_CACHE_PUBLISH_HOST and NIX_CACHE_SCOPE\n' >&2
    return 2
  fi

  copy_cmd=(nix copy --substitute-on-destination --to "$NIX_DEST_STORE_URL")
  if [[ -n "$impure" ]]
  then
    path_info_cmd+=(--impure)
    paths_query+=(--impure)
    copy_cmd+=(--impure)
  fi

  for ref in "${refs[@]}"
  do
    if cached="$(cached_output_paths "$ref" "$impure" 2>/dev/null)"
    then
      retain_ref "$ref" "$cached"
      publish_s3_ref "$ref" "$cached"
      continue
    fi
    if [[ -z "${NIX_STORE_PRIVKEY:-}" ]]
    then
      printf 'NIX_STORE_PRIVKEY is required to upload new outputs\n' >&2
      return 2
    fi
    closure_json="$("${path_info_cmd[@]}" --json "$ref")"
    ssh "$NIX_CACHE_PUBLISH_HOST" /run/current-system/sw/bin/nix-cache-retain capacity <<< "$closure_json"

    key_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$key_file'" RETURN
    umask 077
    printf '%s' "$NIX_STORE_PRIVKEY" > "$key_file"
    "${path_info_cmd[@]}" "$ref" | nix store sign --key-file "$key_file" --stdin
    "${copy_cmd[@]}" "$ref"
    paths="$("${paths_query[@]}" "$ref")"
    paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' <<< "$paths")"
    retain_ref "$ref" "$paths_json"
    publish_s3_ref "$ref" "$paths_json"
  done
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

build_home() {
  local home="$1"
  local system
  local use_builders

  system="$(home_system "$home")"
  use_builders=
  if [[ "$system" == "aarch64-linux" ]]
  then
    use_builders=1
  fi

  build_ref "$(home_ref "$home")" "$use_builders" ""
}

copy_home() {
  local home="$1"

  copy_refs "" "$(home_ref "$home")"
}

build_droid() {
  local droid="$1"
  local system
  local use_builders

  system="$(droid_system "$droid")"
  use_builders=
  if [[ "$system" == "aarch64-linux" ]]
  then
    use_builders=1
  fi

  build_ref "$(droid_ref "$droid")" "$use_builders" 1
}

copy_droid() {
  local droid="$1"

  copy_refs 1 "$(droid_ref "$droid")"
}

main() {
  local copy
  local check_cache
  local nonfree
  local oci
  local pkg=""
  local host=""
  local home=""
  local droid=""
  local system=""

  copy=
  check_cache=
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
      --home)
        home="${2:-}"
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
      --check-cache)
        check_cache=1
        shift
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

  if [[ -n "$pkg" && ( -n "$host" || -n "$home" || -n "$droid" ) ]]
  then
    echo "Choose exactly one of --pkg, --host, --home or --droid" >&2
    return 2
  fi

  if [[ -z "$pkg" && -z "$host" && -z "$home" && -z "$droid" ]]
  then
    echo "Missing --pkg, --host, --home or --droid" >&2
    usage >&2
    return 2
  fi

  if [[ -n "$check_cache" ]]
  then
    local ref impure cached
    impure="$nonfree"
    if [[ -n "$copy" ]]
    then
      printf 'Choose either --copy or --check-cache\n' >&2
      return 2
    fi
    if [[ -n "$pkg" ]]
    then
      [[ -n "$system" ]] || return 2
      ref="$(package_ref "$pkg" "$system")"
    elif [[ -n "$host" ]]
    then
      ref="$(host_ref "$host")"
    elif [[ -n "$home" ]]
    then
      ref="$(home_ref "$home")"
    else
      ref="$(droid_ref "$droid")"
      impure=1
    fi
    cached="$(cached_output_paths "$ref" "$impure" 2>/dev/null)" || return 1
    retain_ref "$ref" "$cached"
    return
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

  if [[ -n "$home" ]]
  then
    if [[ -n "$copy" ]]
    then
      copy_home "$home"
    else
      build_home "$home"
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
