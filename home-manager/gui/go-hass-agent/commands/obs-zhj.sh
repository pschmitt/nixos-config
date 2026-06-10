#!/usr/bin/env bash
# Runs the existing zhj-backed OBS workflows so Home Assistant button presses
# keep the current side effects (scene helpers, mic overlay sync, notifications).

usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND
EOF
}

import_user_environment() {
  local line

  while IFS= read -r line
  do
    [[ -z "$line" || "$line" == PATH=* ]] && continue
    export "${line?}"
  done < <(systemctl --user show-environment 2>/dev/null || true)
}

main() {
  set -euo pipefail

  if [[ $# -ne 1 ]]
  then
    usage >&2
    return 2
  fi

  import_user_environment
  exec zhj obs.zsh "$1"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  main "$@"
fi
