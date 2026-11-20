# vim:set ft=bash ts=2 sw=2 et:
# shellcheck shell=bash

# Global API Key
bitwarden_password() {
  zhj rbw::get "$@"
}
