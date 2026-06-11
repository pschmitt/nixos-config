# Home Assistant secrets for user tooling (eg. zhj hass-cli, see the
# homeassistant zsh plugin), exposed at
# ~/.config/sops-nix/secrets/home-assistant/.
{ config, ... }:
{
  sops.secrets = {
    "home-assistant/server" = { };
    # The long-lived access token is host-specific
    "home-assistant/token".sopsFile = config.host.sopsFile;
  };
}
