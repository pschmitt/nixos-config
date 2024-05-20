#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

find .. -type f -name "*.sops.*" -not -iname ".sops.yaml*" -exec sops updatekeys -y {} \;
