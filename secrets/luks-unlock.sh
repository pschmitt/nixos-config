#!/usr/bin/env bash

DOMAIN="${DOMAIN:-brkn.lol}"
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
    --dryrun|--dry-run|-k)
      DRY_RUN=1
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

if [[ -z "$SSH_HOST" ]]
then
  if ! SSH_HOST="$(dig +short @1.1.1.1 A "${TARGET_HOST}.${DOMAIN}" | head -1)" || \
     [[ -z "$SSH_HOST" ]]
  then
    echo "Error: Failed to resolve SSH host for ${TARGET_HOST}.${DOMAIN}" >&2
    return 1
  fi
fi

SSH_ARGS+=("$@")

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

# sops
if ! PASSPHRASE=$(sops --decrypt --extract '["luks"]["root"]' "../hosts/${TARGET_HOST}/luks.sops.yaml") || \
   [[ -z "$PASSPHRASE" ]]
then
  echo "Failed to get passphrase for ${TARGET_HOST}" >&2
  exit 1
fi

if [[ -n "$DRY_RUN" ]]
then
  echo "DRY RUN: Would unlock LUKS on ${TARGET_HOST} with passphrase: '${PASSPHRASE}'"
else
  ssh "${SSH_ARGS[@]}" -l "$SSH_USER" "$SSH_HOST" \
    systemd-tty-ask-password-agent <<<"$PASSPHRASE"
fi
