#!/usr/bin/env bash
# Unlock the GNOME keyring using the sops-provisioned password (no plaintext,
# no zhj). Triggered as a go-hass-agent button.
set -euo pipefail

secret="${XDG_CONFIG_HOME:-$HOME/.config}/sops-nix/secrets/gnome-keyring/password"
if [[ ! -r "$secret" ]]; then
  echo "keyring password secret not found at $secret" >&2
  exit 1
fi

printf '%s' "$(< "$secret")" | gnome-keyring-unlock
