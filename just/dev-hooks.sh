#!/usr/bin/env bash
# (Re)install the git-hooks.nix pre-commit hook from the dev shell without
# entering it, and pin that shell with a GC root so a garbage collection
# can't remove the pre-commit binary the hook calls.
# The shell is evaluated on a remote builder by default, since some hosts
# (fnuc) must not run Nix evaluations themselves.

usage() {
  cat <<EOF
Usage: $(basename "$0") [--builder HOST | --local]

  -b, --builder HOST  Evaluate the dev shell on HOST (default: rofl-13)
  -l, --local         Evaluate the dev shell on this host
  -h, --help          Show this help
EOF
}

# Output: path of the dev shell env in the local store
build_remote() {
  local builder="$1"
  local env_script="$2"
  local remote_dir="build/nixos-config"
  local env_path

  rsync -a --delete --exclude .git ./ "${builder}:${remote_dir}/" >&2
  # shellcheck disable=SC2029
  ssh "$builder" "cd ${remote_dir} && rm -rf .git && nix print-dev-env --profile ~/build/nixos-config-devshell path:." > "$env_script"
  env_path=$(ssh "$builder" readlink -f build/nixos-config-devshell)
  nix copy --from "ssh-ng://${builder}" "$env_path" >&2
  printf '%s' "$env_path"
}

build_local() {
  local env_script="$1"
  local profile
  profile="$(git rev-parse --absolute-git-dir)/devshell-profile"

  nix print-dev-env --profile "$profile" . > "$env_script"
  readlink -f "$profile"
}

main() {
  local builder="rofl-13"
  local local_build
  local env_script env_path gcroot

  while [[ -n "${1:-}" ]]
  do
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      -b|--builder)
        builder="${2:-}"
        shift 2
        ;;
      -l|--local)
        local_build=1
        shift
        ;;
      *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  done

  cd "$(git rev-parse --show-toplevel)" || return 9

  env_script=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$env_script'" EXIT

  if [[ -n "${local_build:-}" ]]
  then
    env_path=$(build_local "$env_script")
  else
    if [[ -z "$builder" ]]
    then
      printf 'Missing builder\n' >&2
      usage >&2
      return 2
    fi
    env_path=$(build_remote "$builder" "$env_script")
  fi

  # The env script ends with eval "$shellHook", which installs the hook
  # and the .pre-commit-config.yaml link.
  bash -c 'source "$1" >/dev/null' _ "$env_script"

  # Replacing the root releases the previous shell to the GC.
  gcroot="$(git rev-parse --absolute-git-dir)/devshell-gcroot"
  nix-store --add-root "$gcroot" --indirect --realise "$env_path" >/dev/null

  printf 'pre-commit hook installed, dev shell pinned: %s -> %s\n' \
    "$gcroot" "$env_path"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
