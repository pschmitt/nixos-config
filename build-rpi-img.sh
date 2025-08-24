#!/usr/bin/env bash

TARGET_HOST="${1:-pica4}"

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

rm -f result
nix build ".#nixosConfigurations.${TARGET_HOST}.config.system.build.sdImage"
tree result
