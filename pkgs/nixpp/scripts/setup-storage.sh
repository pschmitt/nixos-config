#!/usr/bin/env bash

set -euo pipefail

main() {
  if [[ $# -ne 0 ]]
  then
    printf 'Usage: termux-setup-storage\n' >&2
    return 2
  fi

  local android_user=$(( $(id -u) / 100000 ))
  local shared="/android/storage/emulated/$android_user"
  local shortcuts="$HOME/storage"
  if [[ ! -r "$shared" || ! -x "$shared" ]]
  then
    nixpp enter --outer -- am broadcast --user "$android_user" \
      -a dev.pschmitt.termux.app.request_storage_permissions dev.pschmitt.termux
    printf '\nGrant storage access in Android, then run termux-setup-storage again.\n' >&2
    return 1
  fi

  if [[ -L "$shortcuts" ]]
  then
    printf 'Existing storage link left in place: %s\n' "$shortcuts" >&2
    return 1
  fi
  mkdir -p -- "$shortcuts"
  link_storage "$shared" shared
  link_storage "$shared/DCIM" dcim
  link_storage "$shared/Documents" documents
  link_storage "$shared/Download" downloads
  link_storage "$shared/Movies" movies
  link_storage "$shared/Music" music
  link_storage "$shared/Pictures" pictures
  printf 'Android storage shortcuts are available in %s\n' "$shortcuts"
}

link_storage() {
  local target="$1" link="$shortcuts/$2"
  if [[ -e "$link" || -L "$link" ]]
  then
    if [[ -L "$link" && $(readlink -- "$link") == "$target" ]]
    then
      return
    fi
    printf 'Existing path left in place: %s\n' "$link" >&2
    return
  fi
  ln -sT -- "$target" "$link"
}

main "$@"

# vim: set ft=sh et ts=2 sw=2 :
