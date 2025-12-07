#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: nix-update.sh [OPTIONS]

Options:
  -p, --package NAME   Update only the specified package (can be repeated)
  -s, --system NAME    Target system for flake evaluation (default: x86_64-linux)
  --build              Build each package after updating
  --commit             Let nix-update commit individual updates
  --list               Print the package list and exit
  -h, --help           Show this help message

Examples:
  ./scripts/nix-update.sh --list
  ./scripts/nix-update.sh --package go-hass-agent --build
  ./scripts/nix-update.sh --system aarch64-linux
USAGE
}

resolve_repo_root() {
  local script_path
  local script_dir

  script_path="${BASH_SOURCE[0]}"
  script_dir=$(
    cd "$(dirname "$script_path")" >/dev/null 2>&1
    pwd -P
  )

  cd "$script_dir/.." >/dev/null 2>&1
  pwd -P
}

discover_packages() {
  local target_system="$1"

  nix eval --json ".#packages.${target_system}" --apply builtins.attrNames |
    jq -er '.[]' | grep -Ev '^(ComicCode|MonoLisa|oracle-cloud-agent)'
}

run_update() {
  local package_name="$1"
  local target_system="$2"
  local args=("--flake" "${package_name}")

  if [[ -n ${build_flag:-} ]]
  then
    args+=("--build")
  fi

  if [[ -n ${commit_flag:-} ]]
  then
    args+=("--commit")
  fi

  echo "Updating ${package_name} for ${target_system}" >&2
  nix run nixpkgs#nix-update -- "${args[@]}"
}

main() {
  local -a packages=()
  local system
  local repo_root
  local build_flag
  local commit_flag
  local list_only
  local system="x86_64-linux"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -p|--package)
        if [[ -z ${2:-} ]]
        then
          echo "Error: --package requires an argument" >&2
          usage >&2
          exit 2
        fi
        packages+=("$2")
        shift 2
        ;;
      -s|--system)
        if [[ -z ${2:-} ]]
        then
          echo "Error: --system requires an argument" >&2
          usage >&2
          exit 2
        fi
        system="$2"
        shift 2
        ;;
      -f|--fail|--fail-fast)
        FAIL_FAST=1
        shift
        ;;
      --build)
        build_flag=1
        shift
        ;;
      --commit)
        commit_flag=1
        shift
        ;;
      --list)
        list_only=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  repo_root=$(resolve_repo_root)
  cd "$repo_root"

  if [[ ${#packages[@]} -eq 0 ]]
  then
    mapfile -t packages < <(discover_packages "$system")
  fi

  if [[ -n ${list_only:-} ]]
  then
    printf "%s\n" "${packages[@]}"
    exit 0
  fi

  if [[ ${#packages[@]} -eq 0 ]]
  then
    echo "No packages found for system '${system}'" >&2
    exit 1
  fi

  local pkg
  for pkg in "${packages[@]}"
  do
    if ! run_update "$pkg" "$system"
    then
      echo "Failed to update package: $pkg" >&2

      if [[ -n $FAIL_FAST ]]
      then
        return 1
      fi
    fi
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
