# Home Assistant secrets for user tooling (eg. zhj hass-cli, see the
# homeassistant zsh plugin), exposed at
# ~/.config/sops-nix/secrets/home-assistant/.
{
  lib,
  osConfig ? null,
  ...
}:
{
  sops.secrets = {
    "home-assistant/server" = { };
  }
  // lib.optionalAttrs (osConfig != null) {
    # The long-lived access token is host-specific
    "home-assistant/token".sopsFile = osConfig.custom.sopsFile;
  };
}
