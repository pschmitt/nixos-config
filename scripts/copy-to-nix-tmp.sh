#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1; pwd -P)"

usage() {
  cat <<'EOF'
Usage: copy-to-nix-tmp.sh [--host HOST] PREFIX

Creates a temporary build directory under /nix/tmp/<prefix>-builds, rsyncs the
current repository into it, and prints the resulting path.

Examples:
  copy-to-nix-tmp.sh hm
  copy-to-nix-tmp.sh --host rofl-11 nixos
EOF
}

target_host=""

while [[ $# -gt 0 ]]
do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --host)
      target_host="${2:-}"
      if [[ -z "$target_host" ]]
      then
        echo "Error: --host requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

prefix="${1:-}"
if [[ -z "$prefix" ]]
then
  echo "Error: PREFIX is required" >&2
  usage >&2
  exit 2
fi

build_parent="/nix/tmp/${prefix}-builds"
template="${prefix}-build-XXXXX"

create_build_dir_local() {
  local build_group
  build_group="$(id -gn)"

  if [[ ! -d "$build_parent" ]]
  then
    if ! mkdir -p "$build_parent" 2>/dev/null
    then
      sudo install -d -m 0775 -o "$USER" -g "$build_group" "$build_parent"
    fi
  fi

  if [[ ! -w "$build_parent" ]]
  then
    sudo chown "$USER:$build_group" "$build_parent"
    sudo chmod 0775 "$build_parent"
  fi

  mktemp -d -p "$build_parent" "$template"
}

create_build_dir_remote() {
  local host="$1"

  ssh "$host" bash -s -- "$build_parent" "$template" <<'EOF'
set -euo pipefail

build_parent="$1"
template="$2"
build_group="$(id -gn)"

if [[ ! -d "$build_parent" ]]
then
  if ! mkdir -p "$build_parent" 2>/dev/null
  then
    sudo install -d -m 0775 -o "$USER" -g "$build_group" "$build_parent"
  fi
fi

if [[ ! -w "$build_parent" ]]
then
  sudo chown "$USER:$build_group" "$build_parent"
  sudo chmod 0775 "$build_parent"
fi

mktemp -d -p "$build_parent" "$template"
EOF
}

if [[ -n "$target_host" ]]
then
  build_dir="$(create_build_dir_remote "$target_host")"
  rsync -az --delete --delete-excluded \
    --exclude '.git*' \
    --exclude 'build/' \
    --exclude 'result' \
    --exclude 'tofu/.terraform/' \
    "${REPO_ROOT}/" "${target_host}:${build_dir}/"
else
  build_dir="$(create_build_dir_local)"
  rsync -az --delete --delete-excluded \
    --exclude '.git*' \
    --exclude 'build/' \
    --exclude 'result' \
    "${REPO_ROOT}/" "${build_dir}/"
fi

printf '%s\n' "$build_dir"

# vim: set ft=sh et ts=2 sw=2 :
