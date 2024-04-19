#!/usr/bin/env bash

TARGET_HOST="$1"
DOMAIN=heimat.dev

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

# NOTE agenix won't let you use "./xxxx"
ssh -t "root@${TARGET_HOST}.${DOMAIN}" cryptsetup-askpass \
  <<<"$(agenix -d "${TARGET_HOST}/luks-passphrase-root.age")"