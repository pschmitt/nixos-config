# vim:set ft=bash ts=2 sw=2 et:
# shellcheck shell=bash

s3_access_key_id() {
  local profile="$1"
  zhj s3::credentials --access-key-id "$profile"
}

s3_secret_access_key() {
  local profile="$1"
  zhj s3::credentials --secret-access-key "$profile"
}
