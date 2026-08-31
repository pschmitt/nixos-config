# Home Assistant secrets for user tooling (eg. zhj hass-cli, see the
# homeassistant zsh plugin), exposed at
# ~/.config/sops-nix/secrets/home-assistant/.
{ config, ... }:
{
  sops.secrets = {
    "home-assistant/server" = { };
    # Use the Philipp Schmitt PAT named `nixos-config (<HOSTNAME>)`; each host
    # has its own token.
    "home-assistant/token".sopsFile = config.host.sopsFile;
  };
}
