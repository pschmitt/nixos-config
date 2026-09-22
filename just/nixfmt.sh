#!/usr/bin/env bash
set -euo pipefail

if [[ -f /etc/profile.d/nix.sh ]]
then
  source /etc/profile.d/nix.sh
fi
mapfile -t files < <(find . -name '*.nix' -print)
if [[ ${#files[@]} -gt 0 ]]
then
  nix run nixpkgs#nixfmt -- "${files[@]}"
else
  echo "No .nix files to format"
fi
