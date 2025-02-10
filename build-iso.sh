#!/usr/bin/env bash

TARGET_HOST="${1:-iso}" # or iso-xmr for example

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

rm -f result
nix build ".#nixosConfigurations.${TARGET_HOST}.config.system.build.isoImage"
tree result
