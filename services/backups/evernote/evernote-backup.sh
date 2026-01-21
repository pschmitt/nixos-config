#!/usr/bin/env bash

DATA_DIR="/srv/evernote-backup/data"

docker run --rm \
  -v "${DATA_DIR}:${DATA_DIR}" \
  -w "$DATA_DIR" \
  vzhd1701/evernote-backup:latest \
  "$@"
