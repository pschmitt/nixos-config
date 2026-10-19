#!/usr/bin/env bash

set -euo pipefail

cleanup_dir=''

cleanup() {
  [[ -z "$cleanup_dir" ]] || rm -rf -- "$cleanup_dir"
}

trap cleanup EXIT

import_key() {
  local runtime_generation=$1
  local payload=$2
  local temporary_dir=$3
  local key_name=$4
  local key_selector=$5
  local passphrase_selector=$6
  local key_file="$temporary_dir/$key_name.asc"
  local passphrase_file="$temporary_dir/$key_name.passphrase"
  local fingerprint

  if ! SOPS_AGE_KEY="$age_key" "$runtime_generation/bin/sops" --decrypt \
    --extract "$key_selector" "$payload" > "$key_file"
  then
    printf 'Could not decrypt the GPG key (%s).\n' "$key_name" >&2
    return 1
  fi
  if ! SOPS_AGE_KEY="$age_key" "$runtime_generation/bin/sops" --decrypt \
    --extract "$passphrase_selector" "$payload" > "$passphrase_file"
  then
    printf 'Could not decrypt the GPG passphrase (%s).\n' "$key_name" >&2
    return 1
  fi
  if [[ ! -s "$key_file" || ! -s "$passphrase_file" ]]
  then
    printf 'GPG key material (%s) is empty.\n' "$key_name" >&2
    return 1
  fi

  "$PREFIX/bin/gpg" --batch --yes --pinentry-mode loopback \
    --passphrase-file "$passphrase_file" --import "$key_file" >/dev/null || return

  fingerprint=$("$PREFIX/bin/gpg" --batch --with-colons \
    --import-options show-only --import "$key_file" \
    | awk -F: '/^fpr:/{print $10; exit}') || return
  if [[ -z "$fingerprint" ]]
  then
    printf 'Could not determine the primary fingerprint for GPG key (%s).\n' "$key_name" >&2
    return 1
  fi

  printf '%s:6:\n' "$fingerprint" \
    | "$PREFIX/bin/gpg" --batch --yes --import-ownertrust >/dev/null || return
  printf 'Imported and trusted GPG key (%s).\n' "$key_name"
}

setup_gpg_keys() {
  local generation=${1:?generation path is required}
  local payload="$generation/home/.local/share/termux-native/gpg.sops.yaml"
  local runtime_generation=${TERMUX_GENERATION:-$generation}
  local ssh_identity="$PREFIX/etc/ssh/ssh_host_ed25519_key"
  local age_key

  [[ -f "$payload" ]] || return 0
  if [[ ! -r "$ssh_identity" ]]
  then
    printf 'Missing Termux SSH host identity; cannot decrypt GPG key payload.\n' >&2
    return 1
  fi

  cleanup_dir=$(mktemp -d "$PREFIX/tmp/nixpp-gpg-keys.XXXXXXXX") || return
  age_key=$("$runtime_generation/bin/ssh-to-age" --private-key -i "$ssh_identity") || return
  umask 077
  export GNUPGHOME="$HOME/.config/gnupg"
  mkdir -p "$GNUPGHOME" || return
  chmod 700 "$GNUPGHOME" || return

  import_key "$runtime_generation" "$payload" "$cleanup_dir" \
    private '["gpg"]["private"]["privateKey"]' '["gpg"]["private"]["passphrase"]' || return
  import_key "$runtime_generation" "$payload" "$cleanup_dir" \
    work '["gpg"]["work"]["privateKey"]' '["gpg"]["work"]["passphrase"]' || return
  unset age_key
}

main() {
  if (($# != 1))
  then
    printf 'Usage: %s GENERATION_PATH\n' "$(basename "$0")" >&2
    return 2
  fi
  setup_gpg_keys "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
