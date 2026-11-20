# vim:set ft=bash ts=2 sw=2 et:
# shellcheck shell=bash

docker_username() {
  local registry="$1"
  zhj docker::credentials --username "$registry"
}

docker_password() {
  local registry="$1"
  zhj docker::credentials --password "$registry"
}
