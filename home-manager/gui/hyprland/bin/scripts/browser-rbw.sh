#!/usr/bin/env bash

# DEBUG
# TRACE=1
if [[ -n "$TRACE" ]]
then
  logfile="${HOME}/script.log"
  exec > >(tee -a "$logfile") 2>&1
  set -x
fi

cd "$(cd "$(dirname "$0")" >/dev/null 2>&1; pwd -P)" || exit 9
source lib.sh

current_domain() {
  zhj browser::current-domain "$@"
}

rbw() {
  zhj rbw-wiit::current-tab-get "$@"
}

main() {
  local needle
  needle="$(current_domain "$@")"
  notify_info "Searching for password for $needle"

  local credentials
  if ! credentials="$(rbw --both "$needle")"
  then
    notify_error "No password found for $needle"
    return 1
  fi

  local username password
  read -r username password <<<"$credentials"

  notify_success "Copied password for $needleUsername: '$username'"
  xcp <<< "$password"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  export PATH=${HOME}/bin:${PATH}
  main "$@"
fi
