#!/usr/bin/env bash

source_env_files() {
  local file
  for file in /etc/containers/env/*.env
  do
    # shellcheck disable=SC1090
    source <(sed -r 's#([^=]+)=(.*)#export \1=\2#' "$file")
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  source_env_files
  exec docker compose "$@"
fi
