# NOTE osConfig is only set when home-manager runs as a NixOS module. On
# standalone home-manager hosts (eg. fnuc) it defaults to null and the service
# must be enabled and wired up manually.
{
  config,
  lib,
  osConfig ? null,
  ...
}:
{
  imports = [ ../../../modules/home-manager/go-hass-agent.nix ];

  config = lib.mkIf (osConfig != null) {
    services.go-hass-agent = {
      enable = lib.mkDefault true;
      mqttUsernameSecret = lib.mkDefault "home-assistant/mqtt/username";
      mqttPasswordSecret = lib.mkDefault "home-assistant/mqtt/password";
    };

    # The MQTT credentials are host-specific
    sops.secrets = lib.mkIf config.services.go-hass-agent.enable {
      "home-assistant/mqtt/username".sopsFile = osConfig.custom.sopsFile;
      "home-assistant/mqtt/password".sopsFile = osConfig.custom.sopsFile;
    };
  };
}
