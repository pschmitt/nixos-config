#!/usr/bin/env bash

DOMAIN="${DOMAIN:-heimat.dev}"
SSH_USER="${SSH_USER:-root}"

SSH_ARGS=(-tt)

while [[ $# -gt 0 ]]
do
  case "$1" in
    -l|--login|-u|--user)
      SSH_USER="$2"
      shift 2
      ;;
    --ssh*|-H)
      SSH_HOST="$2"
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

TARGET_HOST="$1"

if [[ -z "$TARGET_HOST" ]]
then
  echo "No target host provided" >&2
  exit 2
fi

shift

SSH_HOST="${SSH_HOST:-${TARGET_HOST}.${DOMAIN}}"
SSH_ARGS+=("$@")

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
# NOTE agenix won't let you use "./xxxx"
if ! PASSPHRASE=$(agenix -d "${TARGET_HOST}/luks-passphrase-root.age") || \
   [[ -z "$PASSPHRASE" ]]
then
  echo "Failed to get passphrase for ${TARGET_HOST}" >&2
  exit 1
fi

ssh "${SSH_ARGS[@]}" -l "$SSH_USER" "$SSH_HOST" \
  systemd-tty-ask-password-agent <<<"$PASSPHRASE"
