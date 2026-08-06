# shellcheck shell=bash

usage() {
  cat <<EOF
Usage: $(basename "$0")

Clone the NixOS configuration into Hermes's dedicated workspace checkout.
EOF
}

main() {
  local flake_dir="${HERMES_FLAKE_DIR:-/srv/hermes/workspace/nixos-config}"

  if [[ -n "${1:-}" ]]
  then
    case "$1" in
      -h|--help)
        usage
        return 0
        ;;
      *)
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        return 2
        ;;
    esac
  fi

  if [[ -e "$flake_dir" ]]
  then
    printf 'NixOS checkout already exists at %s\n' "$flake_dir" >&2
    return 1
  fi

  mkdir -p "$(dirname "$flake_dir")"
  gh-brkn-lol repo clone pschmitt/nixos-config "$flake_dir"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
