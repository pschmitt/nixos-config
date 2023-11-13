#!/usr/bin/env bash

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

AGE_KEY="${HOME}/.ssh/id_ed25519"
SOURCE="${1:-fonts.zip.age}"
DEST="fonts.zip"

rm -f "$DEST"

if age --decrypt --identity "$AGE_KEY" "$SOURCE" > "$DEST"
then
  echo "Decrypted $SOURCE to $DEST"
  exit 0
else
  echo "Failed to decrypt $SOURCE"
  exit 1
fi
