#!/usr/bin/env bash

CONFIGURATION="${1:-${HOSTNAME:-$(hostname)}}"

nix --extra-experimental-features repl-flake repl ".#nixosConfigurations.$CONFIGURATION"
