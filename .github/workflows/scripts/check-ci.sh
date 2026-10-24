#!/usr/bin/env bash

set -euo pipefail

main() {
  # actionlint 1.7.12 predates GitHub's concurrency queue support.
  # Ignore only this new key; retain all other workflow validation.
  actionlint -ignore 'unexpected key "queue" for "concurrency" section' \
    .github/workflows/*.yaml .github/workflows/*.yml
  shellcheck .github/actions/*/*.sh .github/workflows/scripts/*.sh scripts/nix-update.sh scripts/nix-update-release-notes.sh profiles/specializations/server/scripts/filesystem-available.sh
  ruff check --isolated --select E4,E7,E9,F,I .github/workflows/scripts/*.py scripts/nix-update-release-notes.py services/harmonia/scripts/*.py .github/tests
  ruff format --isolated --check .github/workflows/scripts/*.py scripts/nix-update-release-notes.py services/harmonia/scripts/*.py .github/tests
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi

# vim: set ft=sh et ts=2 sw=2 :
