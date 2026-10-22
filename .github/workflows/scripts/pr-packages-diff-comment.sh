#!/usr/bin/env bash

set -euo pipefail

export NIXPKGS_ALLOW_UNFREE=1

exec python3 "$(dirname "${BASH_SOURCE[0]}")/pr-impact.py" "$@"

# vim: set ft=sh et ts=2 sw=2 :
