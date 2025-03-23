#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

TARGET_DISK="data" ./decrypt-luks-passphrase.sh
