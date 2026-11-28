#!/usr/bin/env bash

exec bash "${BASH_SOURCE[0]%/*}/git-update.sh" --prune-merged "$@"

# vim: set ft=sh et ts=2 sw=2 :
