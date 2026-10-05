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
  while IFS= read -r package
  do
    # shellcheck disable=SC2016
    installed=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)
    if [[ "$installed" != 'install ok installed' ]]
    then
      printf 'Missing base package: %s. Run bootstrap.sh first.\n' "$package" >&2
      return 1
    fi
  done < "$root/generations/$generation/base-packages.txt"
  "$root/generations/$generation/bin/termux-nix-hello" || return
  TERMUX_GENERATION="$root/generations/$generation" \
    TERMUX_NATIVE_ZDOTDIR="$root/generations/$generation/home/.config/zsh" \
    PATH="$root/generations/$generation/bin:$PATH" \
    timeout 45 "$PREFIX/bin/zsh" -f "$root/generations/$generation/shell/check-pty.zsh" \
    "$root/generations/$generation" || return
  ln -s "generations/$generation" "$root/.next" || return
  mv -Tf "$root/.next" "$root/current" || return
  printf 'Activated %s. Start the managed shell with:\n  exec "%s/bin/zsh" -l\n' \
    "$generation" "$PREFIX"
}

transaction() (
  local action=$1 archive=$2 generation=$3
  local root="$HOME/.local/share/termux-native" stage actual owns_lock=1
  mkdir -p "$root/generations" || return
  if [[ "${TERMUX_NATIVE_LOCK_HELD:-}" == 1 ]]
  then
    [[ -d "$root/.lock" ]] || return 1
    owns_lock=0
  else
    mkdir "$root/.lock" || return
  fi
  if (( owns_lock )); then
    trap 'rm -f -- "$root/.next"; rmdir -- "$root/.lock"' EXIT
  else
    trap 'rm -f -- "$root/.next"' EXIT
  fi
  if [[ "$action" == install || "$action" == preflight ]]
  then
    stage=$(mktemp -d "$root/generations/.stage.XXXXXXXX") || return
    # Verify the private copy that will be extracted, not a mutable download.
    cp -- "$archive" "$stage/archive.tar.gz" || return
    actual=$(sha256sum "$stage/archive.tar.gz") || return
    if [[ "${actual%% *}" != "$generation" ]]
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
      rm -- "$stage/archive.tar.gz" || return
      rmdir "$stage" || return
      else
        printf 'Generation already exists; reusing it: %s\n' "$generation"
        chmod -R u+w -- "$stage" || return
        rm -rf -- "$stage" || return
      fi
    fi
  if [[ "$action" == preflight ]]
  then
    local generation_root="$root/generations/$generation"
    if [[ ! -x "$generation_root/bin/termux-nix-hello" ||
          ! -f "$generation_root/base-packages.txt" ||
          ! -f "$generation_root/zshenv" ||
          ! -f "$generation_root/shell/check-pty.zsh" ||
          ! -f "$generation_root/shell/smoke-test.zsh" ]]
    then
      printf 'Bundle is missing required Termux generation files: %s\n' "$generation" >&2
      return 1
    fi
    "$generation_root/bin/termux-nix-hello" || return
    printf 'Preflight passed for generation %s.\n' "$generation"
    return 0
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
  transaction "$action" "$archive" "$generation"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
