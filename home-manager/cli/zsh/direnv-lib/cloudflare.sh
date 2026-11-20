# vim:set ft=bash ts=2 sw=2 et:
# shellcheck shell=bash

# Global API Key
cloudflare_api_key() {
  zhj cloudflare::api-key
}

cloudflare_api_token() {
  local profile="$1"
  zhj cloudflare::api-token "$profile"
}
