#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: nix-update.sh [OPTIONS]

Options:
  -p, --package NAME   Update only the specified package (can be repeated)
  -s, --system NAME    Target system for flake evaluation (can be repeated; default: x86_64-linux)
  --no-update-script   Do not invoke passthru.updateScript even if present
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
    jq -r '.[]'
}

is_ignored_package() {
  local package_name="$1"
  shift
  local ignored

  for ignored in "$@"
  do
    if [[ "$ignored" == "$package_name" ]]
    then
      return 0
    fi
  done

  return 1
}

has_update_script() {
  local package_name="$1"
  local target_system="$2"
  local key="${package_name}@${target_system}"
  local result

  if [[ -n ${package_has_update_script[$key]:-} ]]
  then
    [[ "${package_has_update_script[$key]}" == "1" ]]
    return
  fi

  if ! result=$(
    nix eval --json ".#packages.${target_system}.${package_name}" \
      --apply 'p: if p ? passthru && p.passthru ? updateScript then true else false' 2>/dev/null
  )
  then
    echo "Warning: could not detect passthru.updateScript for ${package_name} (${target_system}); continuing without." >&2
    package_has_update_script[$key]=0
    return 1
  fi

  if [[ "$result" == "true" ]]
  then
    package_has_update_script[$key]=1
    return 0
  fi

  package_has_update_script[$key]=0
  return 1
}

run_update() {
  local package_name="$1"
  local target_system="$2"

  # NOTE We need to set pure-eval to false to allow building nonfree pkgs
  local args=(--flake "$package_name" --format --option pure-eval false)

  if [[ -n ${use_update_script:-} ]] && has_update_script "$package_name" "$target_system"
  then
    args+=(--use-update-script)
  fi

  if [[ -n ${build_flag:-} ]]
  then
    args+=(--build)
  fi

  if [[ -n ${commit_flag:-} ]]
  then
    args+=(--commit)
  fi

  echo "Updating ${package_name} for ${target_system}" >&2

  export NIXPKGS_ALLOW_UNFREE=1
  nix run --impure nixpkgs#nix-update -- "${args[@]}"
}

main() {
  local -a packages=()
  local repo_root
  local build_flag
  local commit_flag
  local fail_fast
  local list_only
  local -a systems=()
  local ignore_config_path
  local -a ignored_packages
  local -A package_has_update_script=()
  local primary_system
  local use_update_script=1

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
        systems+=("$2")
        shift 2
        ;;
      -f|--fail|--fail-fast)
        fail_fast=1
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
      --no-update-script)
        use_update_script=
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

  if [[ ${#systems[@]} -eq 0 ]]
  then
    systems=("x86_64-linux")
  fi

  repo_root=$(resolve_repo_root)
  cd "$repo_root"

  if [[ -f /etc/profile.d/nix.sh ]]
  then
    # shellcheck disable=SC1091
    source /etc/profile.d/nix.sh
  fi

  ignore_config_path="$repo_root/pkgs/nix-update.json"

  if [[ -f "$ignore_config_path" ]]
  then
    mapfile -t ignored_packages < <(jq -r '.ignoredPackages // [] | .[]' "$ignore_config_path")
  fi

  if [[ ${#packages[@]} -eq 0 ]]
  then
    primary_system="${systems[0]}"
    mapfile -t packages < <(discover_packages "$primary_system")
  fi

  local -a filtered_packages
  local pkg

  for pkg in "${packages[@]}"
  do
    if is_ignored_package "$pkg" "${ignored_packages[@]}"
    then
      echo "Skipping ignored package: $pkg" >&2
      continue
    fi

    filtered_packages+=("$pkg")
  done

  packages=("${filtered_packages[@]}")

  if [[ -n ${list_only:-} ]]
  then
    printf "%s\n" "${packages[@]}"
    exit 0
  fi

  if [[ ${#packages[@]} -eq 0 ]]
  then
    echo "No packages found for system(s) '${systems[*]}'" >&2
    exit 1
  fi

  local pkg
  local system
  for pkg in "${packages[@]}"
  do
    for system in "${systems[@]}"
    do
      if ! run_update "$pkg" "$system"
      then
        echo "Failed to update package: $pkg (${system})" >&2

        if [[ -n ${fail_fast:-} || ${#packages[@]} -eq 1 ]]
        then
          return 1
        fi
      fi
    done
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
