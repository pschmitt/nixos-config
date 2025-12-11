#!/usr/bin/env bash

usage() {
  cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  -p, --package NAME   Update only the specified package (can be repeated)
  -s, --system NAME    Target system for flake evaluation (can be repeated; default: x86_64-linux)
  --no-update-script   Do not invoke passthru.updateScript even if present
  --build              Build each package after updating
  --commit             Let nix-update commit individual updates
  --fail               Stop on first failure (default: continue on failure)
  --proprietary        Include proprietary packages in the update
  --list               Print the package list
  -h, --help           Show this help message

Examples:
  $(basename "$0") --list
  $(basename "$0") --package go-hass-agent --build
  $(basename "$0") --system aarch64-linux
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

get_proprietary_packages() {
  local target_system="$1"
  # shellcheck disable=SC2016
  NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure --expr "
    let
      flake = builtins.getFlake (builtins.toString ./.);
      pkgs = flake.packages.${target_system};

      checkPkg = n:
        let
          pkg = pkgs.\${n};
          # Check proprietarySource
          propSrc = builtins.tryEval (pkg.proprietarySource or null);
          hasPropSrc = propSrc.success && propSrc.value != null;

          # Check license
          meta = builtins.tryEval (pkg.meta or {});
          license = meta.value.license or {};

          isUnfree = if meta.success then
            (if builtins.isList license then
              builtins.any (l: (l.free or true) == false) license
            else
              (license.free or true) == false)
            else false;
        in hasPropSrc || isUnfree;

      proprietaryPkgs = builtins.filter checkPkg (builtins.attrNames pkgs);
    in
      proprietaryPkgs
  " | jq -r '.[]'
}

get_package_position() {
  local package_name="$1"
  local target_system="$2"

  NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure --expr "
    let
      flake = builtins.getFlake (builtins.toString ./.);
      pkg = flake.packages.${target_system}.${package_name};
    in
      pkg.meta.position or null
  " 2>/dev/null
}

is_local_package() {
  local package_name="$1"
  local target_system="$2"

  local position
  if ! position="$(get_package_position "$package_name" "$target_system" | jq -r '.')"
  then
    echo "Warning: could not detect source path for ${package_name} (${target_system}); continuing." >&2
    return 1
  fi

  if [[ -z "$position" || "$position" == "null" ]]
  then
    return 1
  fi

  if [[ "$position" == */pkgs/local/* ]]
  then
    return 0
  fi

  return 1
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

is_proprietary_package() {
  local package_name="$1"
  shift

  local proprietary
  for proprietary in "$@"
  do
    if [[ "$proprietary" == "$package_name" ]]
    then
      return 0
    fi
  done

  return 1
}

has_update_script() {
  local package_name="$1"
  local target_system="$2"

  local result
  if ! result=$(
    nix eval --json ".#packages.${target_system}.${package_name}" \
      --apply 'p:
        if p ? passthru && p.passthru ? updateScript then
          let
            script = p.passthru.updateScript;
          in
            if builtins.isList script && builtins.length script > 0 then
              let
                name = builtins.baseNameOf (builtins.head script);
              in
                name != "nix-update" || builtins.length script > 1
            else if builtins.isString script || builtins.isPath script then
              let
                name = builtins.baseNameOf script;
              in
                name != "nix-update"
            else if builtins.isAttrs script && script ? command then
              true
            else
              false
        else
          false'
  )
  then
    echo "Warning: could not detect passthru.updateScript for ${package_name} (${target_system}); continuing without." >&2
    return 1
  fi

  if [[ "$result" == "true" ]]
  then
    return 0
  fi

  return 1
}

run_update() {
  local package_name="$1"
  local target_system="$2"

  # NOTE We need to set pure-eval to false to allow building nonfree pkgs
  local args=(--flake "$package_name" --format --option pure-eval false)

  if has_update_script "$package_name" "$target_system"
  then
    if [[ "$package_name" == "oracle-cloud-agent" ]]
    then
      local repo_root
      repo_root="$(git rev-parse --show-toplevel)"

      GIT_ROOT="$repo_root" \
        SOURCES_JSON_PATH="$repo_root/pkgs/oci/oracle-cloud-agent/sources.json" \
        "$repo_root/pkgs/oci/oracle-cloud-agent/update.sh"
      return
    fi

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

  local git_root
  if ! git_root="$(git rev-parse --show-toplevel)" || [[ -z "$git_root" ]]
  then
    echo "Error: Could not determine git root" >&2
    return 1
  fi
  export GIT_ROOT="$git_root"

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
  local include_proprietary
  local -a systems=()
  local ignore_config_path
  local -a ignored_packages
  local -a proprietary_packages
  local primary_system

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -p|--package)
        if [[ -z ${2:-} ]]
        then
          echo "Error: --package requires an argument" >&2
          usage >&2
          return 2
        fi
        packages+=("$2")
        shift 2
        ;;
      -s|--system)
        if [[ -z ${2:-} ]]
        then
          echo "Error: --system requires an argument" >&2
          usage >&2
          return 2
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
      --proprietary|--proprietary-garbage|--garbage)
        include_proprietary=1
        shift
        ;;
      --list)
        list_only=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        echo "Error: Unknown option '$1'" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  if [[ ${#systems[@]} -eq 0 ]]
  then
    systems=("x86_64-linux")
  fi

  repo_root=$(resolve_repo_root)
  cd "$repo_root"

  ignore_config_path="$repo_root/pkgs/nix-update.json"

  if [[ -f "$ignore_config_path" ]]
  then
    mapfile -t ignored_packages < <(jq -er '
      .ignoredPackages // [] | .[]
    ' "$ignore_config_path")
  fi

  primary_system="${systems[0]}"

  if [[ -z ${include_proprietary:-} ]]
  then
    mapfile -t proprietary_packages < <(get_proprietary_packages "$primary_system")
  fi

  case "${#packages[@]}" in
    0)
      mapfile -t packages < <(discover_packages "$primary_system")
      ;;
    1)
      # we should return 1 when we try to update a single pkg and it fails
      fail_fast=1
      ;;
  esac

  local -a filtered_packages
  local pkg

  for pkg in "${packages[@]}"
  do
    if is_ignored_package "$pkg" "${ignored_packages[@]}"
    then
      echo "Skipping ignored package: $pkg" >&2
      continue
    fi

    if [[ -z ${include_proprietary:-} ]] && is_proprietary_package "$pkg" "${proprietary_packages[@]}"
    then
      if ! has_update_script "$pkg" "$primary_system"
      then
        echo "Skipping proprietary package (no update script): $pkg" >&2
        continue
      fi
    fi

    if is_local_package "$pkg" "$primary_system"
    then
      echo "Skipping local package: $pkg" >&2
      continue
    fi

    filtered_packages+=("$pkg")
  done

  packages=("${filtered_packages[@]}")

  if [[ -n ${list_only:-} ]]
  then
    printf "%s\n" "${packages[@]}"
    return 0
  fi

  if [[ ${#packages[@]} -eq 0 ]]
  then
    echo "No packages found for system(s) '${systems[*]}'" >&2
    return 1
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

        if [[ -n ${fail_fast:-} ]]
        then
          return 1
        fi
      fi
    done
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -euo pipefail

  main "$@"
fi
