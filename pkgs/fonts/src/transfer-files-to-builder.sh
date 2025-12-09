#!/usr/bin/env bash


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  TARGET_USER="${TARGET_USER:-github-actions}"
  TARGET_HOST="${TARGET_HOST:-rofl-03.brkn.lol}"

  cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9

  if ! ../../../scripts/fetch-proprietary-garbage.sh .
  then
    echo "Failed to fetch font files" >&2
    exit 1
  fi

  ssh "${TARGET_USER}@${TARGET_HOST}" mkdir -p src
  scp ./*.zip "${TARGET_USER}@${TARGET_HOST}:src"
fi
