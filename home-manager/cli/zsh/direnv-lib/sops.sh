# vim:set ft=bash ts=2 sw=2 et:
# shellcheck shell=bash

# usage: use sops [FILE]
use_sops() {
  local sops_file="$1"
  if [[ -z "$sops_file" ]]
  then
    local sops_files
    mapfile -t sops_files < <(find "$PWD" -mindepth 1 -maxdepth 1 -type f \
      -iname '*.sops.*' -not -name ".sops.yaml")
    sops_file=${sops_files[0]} # default to first file
  fi

  eval "$(sops -d --output-type dotenv "$sops_file" | \
    sed -r 's#([^=]+)=(.*)#\U\1=\E\2#' | \
    direnv dotenv bash /dev/stdin)"
  watch_file "$sops_file"
}
