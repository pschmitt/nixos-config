#!/usr/bin/env bash

set -euo pipefail

setup_nixpp_cache() {
  local generation=${1:?generation path is required}
  local payload="$generation/home/.local/share/termux-native/nix-cache.sops.yaml"
  local runtime_generation=${TERMUX_GENERATION:-$generation}
  local age_key temporary_dir credentials_tmp access_key secret_key

  [[ -f "$payload" ]] || return 0
  if [[ ! -s "$HOME/.ssh/id_ed25519" ]]
  then
    printf 'Missing personal SSH identity; cannot decrypt Niks3 credentials.\n' >&2
    return 1
  fi

  mkdir -p "$PREFIX/tmp" "$HOME/.aws" || return
  chmod 0700 "$HOME/.aws" || return
  temporary_dir=$(mktemp -d "$PREFIX/tmp/nixpp-cache-credentials.XXXXXXXX") || return
  credentials_tmp=$(mktemp "$HOME/.aws/.credentials.XXXXXXXX") || return
  cleanup_nixpp_cache() {
    [[ -z "${credentials_tmp:-}" ]] || rm -f -- "$credentials_tmp"
    if [[ -n "${temporary_dir:-}" ]]
    then
      rm -f -- "$temporary_dir/access-key" "$temporary_dir/secret-key"
      rmdir "$temporary_dir" 2>/dev/null || true
    fi
  }
  trap cleanup_nixpp_cache EXIT

  age_key=$("$runtime_generation/bin/ssh-to-age" --private-key -i "$HOME/.ssh/id_ed25519") || return
  if ! SOPS_AGE_KEY="$age_key" "$runtime_generation/bin/sops" decrypt \
    --extract '["niks3"]["client-access-key"]' "$payload" \
    > "$temporary_dir/access-key"
  then
    unset age_key
    printf 'Could not decrypt the Niks3 access key.\n' >&2
    return 1
  fi
  if ! SOPS_AGE_KEY="$age_key" "$runtime_generation/bin/sops" decrypt \
    --extract '["niks3"]["client-secret-key"]' "$payload" \
    > "$temporary_dir/secret-key"
  then
    unset age_key
    printf 'Could not decrypt the Niks3 secret key.\n' >&2
    return 1
  fi
  unset age_key

  access_key=$(<"$temporary_dir/access-key")
  secret_key=$(<"$temporary_dir/secret-key")
  if [[ -z "$access_key" || -z "$secret_key" ||
    "$access_key" == *$'\n'* || "$secret_key" == *$'\n'* ]]
  then
    unset access_key secret_key
    printf 'The decrypted Niks3 credentials are empty or malformed.\n' >&2
    return 1
  fi

  {
    printf '[niks3]\n'
    printf 'aws_access_key_id = %s\n' "$access_key"
    printf 'aws_secret_access_key = %s\n' "$secret_key"
  } > "$credentials_tmp"
  unset access_key secret_key
  chmod 0600 "$credentials_tmp" || return
  mv -f -- "$credentials_tmp" "$HOME/.aws/credentials" || return
  credentials_tmp=''
  printf 'Installed private Niks3 read credentials.\n' >&2
}

main() {
  PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
  export PREFIX
  setup_nixpp_cache "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
