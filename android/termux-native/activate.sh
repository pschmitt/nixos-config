#!/usr/bin/env bash

usage() {
  printf 'Usage: %s preflight ARCHIVE TRUSTED_SHA256 | install ARCHIVE TRUSTED_SHA256 | rollback GENERATION_SHA256\n' "$(basename "$0")"
}

check_host() {
  if [[ "${PREFIX:-}" != /data/data/com.termux/files/usr || "$(uname -m)" != aarch64 ]]
  then
    printf 'This prototype requires standard com.termux on aarch64.\n' >&2
    return 1
  fi
  local api
  api=$(getprop ro.build.version.sdk) || return
  if [[ ! "$api" =~ ^[0-9]+$ ]] || ((api < 35))
  then
    printf 'Android API 35 or newer is required.\n' >&2
    return 1
  fi
}

switch_generation() {
  local root=$1 generation=$2 package installed
  local -a packages=()
  "$root/generations/$generation/bin/termux-nix-hello" || return
  mapfile -t packages < "$root/generations/$generation/base-packages.txt"
  for package in "${packages[@]}"
  do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
    then
      printf 'Invalid Termux package name in generation: %s\n' "$package" >&2
      return 1
    fi
  done
  if ((${#packages[@]} > 0))
  then
    pkg install -y "${packages[@]}" || return
  fi
  while IFS= read -r package
  do
    # shellcheck disable=SC2016
    installed=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)
    if [[ "$installed" != 'install ok installed' ]]
    then
      printf 'Termux APT did not install required package: %s\n' "$package" >&2
      return 1
    fi
  done < "$root/generations/$generation/base-packages.txt"
  timeout 45 "$PREFIX/bin/zsh" -f "$root/generations/$generation/shell/check-pty.zsh" \
    "$root/generations/$generation" || return
  ln -s "generations/$generation" "$root/.next" || return
  mv -Tf "$root/.next" "$root/current" || return
  printf 'Activated %s. Start the managed shell with:\n  exec "%s/bin/zsh" -l\n' \
    "$generation" "$PREFIX"
}

preflight_archive() (
  local archive=$1 generation=$2 stage actual package
  local -a packages=()
  # Invoked by the EXIT trap.
  # shellcheck disable=SC2329
  cleanup_preflight() {
    chmod -R u+w -- "$stage" 2>/dev/null || true
    command rm -rf -- "$stage"
  }
  stage=$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/termux-native-preflight.XXXXXXXX") || return
  trap cleanup_preflight EXIT
  cp -- "$archive" "$stage/archive.tar.gz" || return
  actual=$(sha256sum "$stage/archive.tar.gz") || return
  if [[ "${actual%% *}" != "$generation" ]]
  then
    printf 'Archive checksum mismatch during preflight.\n' >&2
    return 1
  fi
  mkdir "$stage/tree" || return
  tar --no-same-owner -xzf "$stage/archive.tar.gz" -C "$stage/tree" || return
  if [[ ! -x "$stage/tree/bin/termux-nix-hello" ||
    ! -s "$stage/tree/base-packages.txt" ]]
  then
    printf 'Generation archive is missing required bootstrap files.\n' >&2
    return 1
  fi
  mapfile -t packages < "$stage/tree/base-packages.txt"
  for package in "${packages[@]}"
  do
    if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
    then
      printf 'Invalid Termux package name in generation: %s\n' "$package" >&2
      return 1
    fi
  done
  "$stage/tree/bin/termux-nix-hello"
)

transaction() (
  local action=$1 archive=$2 generation=$3
  local root="$HOME/.local/share/termux-native" stage actual owns_lock=1
  mkdir -p "$root/generations" || return
  mkdir "$root/.lock" || return
  trap 'command rm -f -- "$root/.next"; rmdir -- "$root/.lock"' EXIT
  if [[ "$action" == install ]]
  then
    stage=$(mktemp -d "$root/generations/.stage.XXXXXXXX") || return
    # Verify the private copy that will be extracted, not a mutable download.
    cp -- "$archive" "$stage/archive.tar.gz" || return
    actual=$(sha256sum "$stage/archive.tar.gz") || return
    actual=${actual:0:64}
    if [[ "$actual" != "$generation" ]]
    then
      printf 'Archive checksum mismatch; staging directory retained: %s\n' "$stage" >&2
      return 1
    fi
    # Input must be our trusted build artifact, not an arbitrary user archive.
    mkdir "$stage/tree" || return
    tar --no-same-owner -xzf "$stage/archive.tar.gz" -C "$stage/tree" || return
    if [[ ! -e "$root/generations/$generation" ]]
    then
      # Nix directories are read-only; Android requires write access to move one.
      chmod u+w "$stage/tree" || return
      mv "$stage/tree" "$root/generations/$generation" || return
      chmod a-w "$root/generations/$generation" || return
      command rm -f -- "$stage/archive.tar.gz" || return
      rmdir "$stage" || return
      else
        printf 'Generation already exists; reusing it: %s\n' "$generation"
        chmod -R u+w -- "$stage" || return
        command rm -rf -- "$stage" || return
      fi
    fi
    if [[ ! -x "$root/generations/$generation/bin/termux-nix-hello" ||
      ! -s "$root/generations/$generation/base-packages.txt" ]]
    then
      printf 'Generation archive is missing required bootstrap files: %s\n' "$generation" >&2
      return 1
    fi
  switch_generation "$root" "$generation"
)

main() {
  local action=${1:-} archive generation
  case "$action" in
    -h | --help)
      usage
      return 0
      ;;
    preflight | install)
      if (($# != 3))
      then
        usage >&2
        return 2
      fi
      archive=$2
      generation=$3
      ;;
    preflight)
      if (($# != 3))
      then
        usage >&2
        return 2
      fi
      archive=$2
      generation=$3
      ;;
    rollback)
      if (($# != 2))
      then
        usage >&2
        return 2
      fi
      archive=
      generation=$2
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
  if [[ ! "$generation" =~ ^[0-9a-f]{64}$ ]]
  then
    printf 'Expected a lowercase SHA-256 digest from a trusted channel.\n' >&2
    return 2
  fi
  check_host || return
  if [[ "$action" == preflight ]]
  then
    preflight_archive "$archive" "$generation"
  else
    transaction "$action" "$archive" "$generation"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
