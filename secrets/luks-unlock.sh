#!/usr/bin/env bash

DOMAIN="${DOMAIN:-heimat.dev}"
SSH_USER="${SSH_USER:-root}"

TARGET_HOST="${1:-${TARGET_HOST}}"
SSH_HOST="${2:-${TARGET_HOST}.${DOMAIN}}"

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

# NOTE agenix won't let you use "./xxxx"
ssh -tt -l "$SSH_USER" "$SSH_HOST" systemd-tty-ask-password-agent \
  <<<"$(agenix -d "${TARGET_HOST}/luks-passphrase-root.age")"
