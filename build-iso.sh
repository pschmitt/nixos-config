#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

rm -f result
nix build '.#nixosConfigurations.iso.config.system.build.isoImage'
tree result
