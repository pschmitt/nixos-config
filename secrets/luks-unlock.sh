#!/usr/bin/env bash

DOMAIN="${DOMAIN:-heimat.dev}"
SSH_USER="${SSH_USER:-root}"

TARGET_HOST="${1:-${TARGET_HOST}}"
SSH_HOST="${2:-${TARGET_HOST}.${DOMAIN}}"

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

SSH_ARGS=(-tt)

while [[ $# -gt 0 ]]
do
  case "$1" in
    -l|--login)
      SSH_USER="$2"
      shift 2
      ;;
    -f|--force|-i|--insecure)
      SSH_ARGS+=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
      shift
      ;;
    *)
      break
      ;;
  esac
done

SSH_ARGS+=("$@")

# NOTE agenix won't let you use "./xxxx"
if ! PASSPHRASE=$(agenix -d "${TARGET_HOST}/luks-passphrase-root.age") || \
   [[ -z "$PASSPHRASE" ]]
then
  echo "Failed to get passphrase for ${TARGET_HOST}" >&2
  exit 1
fi

ssh "${SSH_ARGS[@]}" -l "$SSH_USER" "$SSH_HOST" \
  systemd-tty-ask-password-agent <<<"$PASSPHRASE"
