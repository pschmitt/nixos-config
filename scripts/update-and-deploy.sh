#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [NIXOS-REBUILD OPTIONS]

Update /etc/nixos and switch to the resulting NixOS configuration.

Options:
  -f, -u, --flake-update  Update flake inputs before rebuilding
  -h, --help              Show this help message

All remaining options are passed to the local deploy command.
EOF
}

checkout_main() {
  local remote_head main_branch current_branch branch

  remote_head="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD || true)"
  main_branch="${remote_head#origin/}"

  if [[ -z "$main_branch" ]]
  then
    for branch in main master
    do
      if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"
      then
        main_branch="$branch"
        break
      fi
    done
  fi

  if [[ -z "$main_branch" ]]
  then
    printf 'Unable to determine the repository main branch\n' >&2
    return 1
  fi

  current_branch="$(git -C "$repo_dir" branch --show-current)"
  if [[ "$current_branch" == "$main_branch" ]]
  then
    return 0
  fi

  printf 'Switching /etc/nixos to %s\n' "$main_branch"
  git -C "$repo_dir" switch "$main_branch"
}

main() {
  local flake_update=0
  local repo_dir="${NIXOS_CONFIG_DIR:-/etc/nixos}"

  while [[ $# -gt 0 ]]
  do
    case "$1" in
      -f|-u|--flake-update)
        flake_update=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ ! -d "$repo_dir/.git" ]]
  then
    printf 'NixOS configuration repository not found: %s\n' "$repo_dir" >&2
    return 1
  fi

  checkout_main
  git -C "$repo_dir" pull --rebase --autostash

  if [[ "$flake_update" -eq 1 ]]
  then
    printf 'Updating flake inputs\n'
    nix flake update --flake "$repo_dir"
  fi

  printf 'Deploying NixOS configuration\n'
  cd "$repo_dir" || return 1
  just deploy "" "$@"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
