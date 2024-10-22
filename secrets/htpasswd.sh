#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") USERNAME [PASSWORD]" >&2
}

gen_password() {
  local password
  password=$(pwgen 69 1)
  echo -e "Generated password: \e[1;32m$password\e[0m" >&2
  echo "$password"
}

HTPASSWD_USERNAME="$1"
HTPASSWD_PASSWORD="$2"

if [[ -z "$HTPASSWD_USERNAME" ]]
then
  usage >&2
  exit 1
fi

if [[ -z "$HTPASSWD_PASSWORD" ]]
then
  HTPASSWD_PASSWORD=$(gen_password)
fi

# NOTE Below requires "comma"
# shellcheck disable=SC2288
, htpasswd -nbB "$HTPASSWD_USERNAME" "$HTPASSWD_PASSWORD" | head -1
