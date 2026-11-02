#!/usr/bin/env bash
# Unlock the GNOME keyring using the sops-provisioned password (no plaintext,
# no zhj). Triggered as a go-hass-agent button.
set -euo pipefail

# oo7 unlocks the login keyring from its systemd credential on start.
if systemctl --user cat oo7-daemon.service >/dev/null 2>&1
then
  exec systemctl --user restart oo7-daemon.service
fi

secret="${XDG_CONFIG_HOME:-$HOME/.config}/sops-nix/secrets/gnome-keyring/password"
if [[ ! -r "$secret" ]]; then
  echo "keyring password secret not found at $secret" >&2
  exit 1
fi

printf '%s' "$(< "$secret")" | gnome-keyring-unlock
