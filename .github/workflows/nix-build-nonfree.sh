#!/usr/bin/env bash

usage() {
  echo "Usage: $0 [--keep-repo] [--ci] [GIT_REF] [PKG]"
}

get_repo() {
  local git_ref="${GIT_REF:-$1}"
  local dest=${DEST:-$PWD}
  local repo="${dest}/nixos-config${git_ref:+-${git_ref}}"

  echo "$repo"
}

clone_repo() {
  local git_ref="${1:-main}"
  local repo_path="${2:-${PWD}/nixos-config.git}"

  rm -rf "$repo_path"
  mkdir -p "$(dirname "$repo_path")"

  git clone --depth 1 https://github.com/pschmitt/nixos-config.git "$repo_path"

  if [[ -n "$git_ref" ]]
  then
    echo "Checking out commit $git_ref" >&2
    git -C "$repo_path" fetch --depth=1 origin "$git_ref"
    git -C "$repo_path" checkout "$git_ref"
  fi
}

build_fonts() {
  local repo="${1:-${PWD}/nixos-config.git}"
  local font_path="${repo}/pkgs/fonts"
  cd "$repo" || exit 9

  "${repo}/pkgs/fonts/src/fetch-fonts.sh" || return 1
  git -C "$repo" add --intent-to-add --all --force
  # export NIXPKGS_ALLOW_UNFREE=1

  local pkg pkg_path
  for pkg_path in $(find "$font_path" -maxdepth 1 -type d | grep -E '(ComicCode|MonoLisa)')
  do
    cd "${pkg_path}" || return 9
    pkg="$(basename "$pkg_path")"
    echo "Building package $pkg at $pkg_path" >&2
    # NOTE --impure is required for nix to read from env (NIXPKGS_ALLOW_UNFREE)
    NIXPKGS_ALLOW_UNFREE=1 nix build --impure --print-build-logs ".#${pkg}"
  done
}

build_pkg() {
  local repo="${1:-${PWD}/nixos-config.git}"
  local pkg="$2"
  local font_path="${repo}/pkgs/fonts"
  cd "$repo" || exit 9

  "${repo}/pkgs/fonts/src/fetch-fonts.sh" || return 1
  git -C "$repo" add --intent-to-add --all --force

  NIXPKGS_ALLOW_UNFREE=1 nix build --impure --print-build-logs ".#${pkg}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  while [[ -n "$*" ]]
  do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --keep-repo|-k)
        KEEP_REPO=1
        shift
        ;;
      --ci)
        CI=1
        shift
        ;;
    esac
  done

  GIT_REF="$1"
  PKG="$2"

  if [[ -n "$CI" ]]
  then
    DEST=$(mktemp -d)
    # unset KEEP_REPO
  fi

  GIT_REPO="$(get_repo "$GIT_REF")"
  clone_repo "$GIT_REF" "$GIT_REPO"

  if [[ -n "$PKG" ]]
  then
    build_pkg "$GIT_REPO" "$PKG"
  else
    build_fonts "$GIT_REPO"
  fi

  RC="$?"

  if [[ -z "$KEEP_REPO" ]]
  then
    rm -rf "$GIT_REPO"
  fi

  exit "$RC"
fi
