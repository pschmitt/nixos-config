#!/usr/bin/env bash

usage() {
  printf 'Usage: %s GENERATION_PATH\n' "$(basename "$0")"
}

setup_cache_credentials() (
  set -uo pipefail
  umask 077
  local generation="$1" payload directory temporary='' age_key
  payload="$generation/home/.local/share/termux-native/cache-credentials.sops.yaml"
  directory="$HOME/.config/nixpp"
  [[ -f "$payload" ]] || return 0
  if [[ ! -r "$PREFIX/etc/ssh/ssh_host_ed25519_key" ]]
  then
    printf 'Missing Termux SSH identity; cannot decrypt cache credentials.\n' >&2
    return 1
  fi
  if [[ -L "$directory" || -L "$directory/cache-credentials" ]]
  then
    printf 'Refusing symlinked cache credential destination.\n' >&2
    return 1
  fi
  mkdir -p -- "$directory" || return 1
  temporary=$(mktemp "$directory/.cache-credentials.XXXXXXXX") || return 1
  trap 'rm -f -- "$temporary"' EXIT
  age_key=$("$generation/bin/ssh-to-age" --private-key -i "$PREFIX/etc/ssh/ssh_host_ed25519_key") || return 1
  if ! SOPS_AGE_KEY="$age_key" "$generation/bin/sops" --decrypt --output-type json "$payload" 2>/dev/null |
    "$PREFIX/bin/jq" -er '
      def credential: type == "string" and test("^[A-Za-z0-9/+=_-]+$");
      if (.access_key | credential) and (.secret_key | credential)
      then "[niks3]\naws_access_key_id = \(.access_key)\naws_secret_access_key = \(.secret_key)"
      else error("invalid cache credentials") end' > "$temporary"
  then
    unset age_key
    printf 'Could not decrypt or validate cache credentials.\n' >&2
    return 1
  fi
  unset age_key
  chmod 600 "$temporary" || return 1
  mv -f -- "$temporary" "$directory/cache-credentials" || return 1
  printf 'Installed read-only cache credentials.\n'
)

main() {
  if [[ "$#" == 1 && ( "$1" == --help || "$1" == -h ) ]]
  then
    usage
    return 0
  fi
  if (( $# != 1 ))
  then
    usage >&2
    return 2
  fi
  setup_cache_credentials "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
