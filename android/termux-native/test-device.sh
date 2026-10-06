#!/usr/bin/env bash

usage() {
  printf 'Usage: %s ARCHIVE TRUSTED_SHA256\n' "$(basename "$0")"
}

main() (
  set -euo pipefail
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]
  then
    usage
    return 0
  fi
  if (($# != 2))
  then
    usage >&2
    return 2
  fi
  local installer archive=$1 first=$2 second broken work selected index first_number second_number
  installer="$(dirname "${BASH_SOURCE[0]}")/activate.sh"
  selected="$HOME/.local/share/termux-native/current"
  index="$HOME/.local/share/termux-native/generation-index.tsv"
  work=$(mktemp -d "${TMPDIR:?}/termux-native-test.XXXXXXXX")
  bash "$installer" install "$archive" "$first"
  [[ "$(readlink "$selected")" == "generations/$first" ]]
  bash "$installer" install "$archive" "$first"
  [[ "$(readlink "$selected")" == "generations/$first" ]]

  mkdir "$work/tree"
  tar -xzf "$archive" -C "$work/tree"
  chmod u+w "$work/tree"
  touch "$work/tree/second-generation"
  tar -czf "$work/second.tar.gz" -C "$work/tree" .
  second=$(sha256sum "$work/second.tar.gz")
  second=${second%% *}
  bash "$installer" install "$work/second.tar.gz" "$second"
  [[ "$(readlink "$selected")" == "generations/$second" ]]
  first_number=$(awk -F '\t' -v id="$first" '$2 == id { print $1 }' "$index")
  second_number=$(awk -F '\t' -v id="$second" '$2 == id { print $1 }' "$index")
  [[ "$first_number" =~ ^[1-9][0-9]*$ && "$second_number" =~ ^[1-9][0-9]*$ ]]
  ((second_number > first_number))

  bash "$installer" rollback "$first_number"
  [[ "$(readlink "$selected")" == "generations/$first" ]]
  bash "$installer" rollback "$second_number"
  [[ "$(readlink "$selected")" == "generations/$second" ]]
  bash "$installer" rollback "$first_number"
  [[ "$(readlink "$selected")" == "generations/$first" ]]
  if bash "$installer" install "$archive" "$(printf '%064d' 0)"
  then
    printf 'FAIL: accepted incorrect checksum\n' >&2
    return 1
  fi
  [[ "$(readlink "$selected")" == "generations/$first" ]]

  chmod u+w "$work/tree/bin"
  chmod u+w "$work/tree/bin/termux-nix-hello"
  rm -- "$work/tree/bin/termux-nix-hello"
  tar -czf "$work/broken.tar.gz" -C "$work/tree" .
  broken=$(sha256sum "$work/broken.tar.gz")
  broken=${broken%% *}
  if bash "$installer" install "$work/broken.tar.gz" "$broken"
  then
    printf 'FAIL: activated a generation with a missing executable\n' >&2
    return 1
  fi
  [[ "$(readlink "$selected")" == "generations/$first" ]]
  printf 'PASS: native execution, plugin load, idempotent switch, update, rollback, hash rejection, failed health check\n'
  printf 'Test fixtures retained at %s\n' "$work"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
