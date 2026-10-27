#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [NIXOS-REBUILD OPTIONS]

Update the NixOS configuration repository and switch to the resulting configuration.
Uses NIXOS_CONFIG_DIR, /etc/nixos, or ~/devel/private/pschmitt/nixos-config.git.

Options:
  -f, -u, --flake-update  Update flake inputs before rebuilding
  -h, --help              Show this help message

All remaining options are passed to the local deploy command.
EOF
}

wait_for_network() {
  local host="github.com" port=443 tries=30

  while (( tries-- > 0 ))
  do
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
    then
      return 0
    fi
    sleep 2
  done

  return 1
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

  printf 'Switching %s to %s\n' "$repo_dir" "$main_branch"
  git -C "$repo_dir" switch "$main_branch"
}

show_diff() {
  local old_system="$1" new_system

  new_system="$(readlink -f /run/current-system)"
  if [[ "$old_system" == "$new_system" ]]
  then
    printf 'System closure unchanged, nothing to diff\n'
    return 0
  fi

  printf 'Changes in the active system:\n'
  nvd --color always diff "$old_system" "$new_system" || true
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

  if [[ -z "${NIXOS_CONFIG_DIR:-}" && ! -e "$repo_dir/.git" ]]
  then
    repo_dir="$HOME/devel/private/pschmitt/nixos-config.git"
  fi

  if [[ ! -e "$repo_dir/.git" ]] || ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    printf 'NixOS configuration repository not found: %s\n' "$repo_dir" >&2
    return 1
  fi

  if ! wait_for_network
  then
    printf 'Warning: network still unreachable after waiting, proceeding anyway\n' >&2
  fi

  checkout_main
  git -C "$repo_dir" pull --rebase --autostash

  if [[ "$flake_update" -eq 1 ]]
  then
    printf 'Updating flake inputs\n'
    nix flake update --flake "$repo_dir"
  fi

  local old_system rc=0
  old_system="$(readlink -f /run/current-system)"

  printf 'Deploying NixOS configuration\n'
  cd "$repo_dir" || return 1
  just deploy "" "$@" || rc=$?

  show_diff "$old_system"
  return "$rc"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
