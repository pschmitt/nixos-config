#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s WORKER PACKAGE FILE\n' "$(basename "$0")"
}

main() {
  if [[ "${1:-}" == -h || "${1:-}" == --help ]]
  then
    usage
    return 0
  fi
  if [[ "$#" != 3 || -z "$1" || -z "$2" || -z "$3" ]]
  then
    usage >&2
    return 2
  fi

  local worker="$1" package="$2" file="$3"
  if [[ ! -f "$file" ]]
  then
    printf '%s: expected a local regular file\n' "$file" >&2
    return 2
  fi

  local source name expected actual
  source=$(NIXPKGS_ALLOW_UNFREE=1 nix eval --json --impure \
    ".#packages.x86_64-linux.$package.proprietarySource") || return 1
  name=$(jq -er '.name | select(type == "string" and length > 0)' <<< "$source") || return 1
  expected=$(jq -er '.sha256 | select(type == "string" and length > 0)' <<< "$source") || return 1
  expected=$(nix hash convert --hash-algo sha256 --to sri -- "$expected") || return 1
  actual=$(nix hash file --type sha256 -- "$file") || return 1
  if [[ "$actual" != "$expected" ]]
  then
    printf '%s: SHA-256 mismatch for %s\nExpected %s\nActual   %s\n' \
      "$file" "$name" "$expected" "$actual" >&2
    return 1
  fi

  rworker setup nix upload-blob "$worker" --name "$name" -- "$file"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
