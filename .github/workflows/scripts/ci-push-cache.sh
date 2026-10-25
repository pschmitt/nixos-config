#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s TARGET STORE_PATH...\n' "$(basename "$0")"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]
  then
    usage
    return 0
  fi
  if [[ $# -lt 2 ]]
  then
    usage >&2
    return 2
  fi
  # Only trusted main jobs receive upload rights. An unset URL permits a
  # staged rollout before the cache server and bucket are available.
  if [[ -z "${NIKS3_SERVER_URL:-}" || "${GITHUB_REF:-}" != "refs/heads/main" ]]
  then
    return 0
  fi

  local target="$1"
  shift
  local cli helper pin path index
  local -a paths=("$@")
  if [[ -n "${NIX_DEST_STORE_URL:-}" ]]
  then
    for path in "${paths[@]}"
    do
      if ! nix path-info "$path" >/dev/null 2>&1
      then
        nix copy --from "$NIX_DEST_STORE_URL" "$path"
      fi
    done
  fi
  # Use the same release as the server; the upstream cache supplies the CLI.
  cli="$(nix build --no-link --print-out-paths 'github:Mic92/niks3/a79dc58832332ebd953974e71160ab69e2371d62#niks3')"
  helper="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/niks3-oidc-token.py"
  pin="$(printf '%s' "$target" | sha256sum | cut -c1-32)"
  index=0
  for path in "${paths[@]}"
  do
    "$cli/bin/niks3" push \
      --server-url "$NIKS3_SERVER_URL" \
      --auth-token-script "python3 $helper" \
      --pin "main-${pin}-${index}" \
      "$path"
    index=$((index + 1))
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
