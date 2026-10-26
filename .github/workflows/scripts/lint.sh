#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'Usage: %s nix|scripts\n' "$(basename "$0")"
}

# Every tracked file of a type, so new files are linted without updating a
# list. Opt out per line or file with the linter's own directives.
tracked() {
  git ls-files -z "$@"
}

lint_nix() {
  statix check
  tracked '*.nix' | xargs -0 deadnix --fail
  tracked '*.nix' | xargs -0 nixfmt --check
}

lint_scripts() {
  tracked '*.sh' | xargs -0 shellcheck
  tracked '*.py' | xargs -0 ruff check
  # Formatting only for the CI tooling, see ruff.toml.
  tracked '.github/*.py' | xargs -0 ruff format --check
}

main() {
  case "${1:-}" in
    nix)
      lint_nix
      ;;
    scripts)
      lint_scripts
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
