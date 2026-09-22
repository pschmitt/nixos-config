{ pkgs, ... }:
{
  imports = [ ../gui/go-hass-agent ];

  services.go-hass-agent = {
    enable = true;
    enableDesktopScripts = false;
    mqttUsernameSecret = "home-assistant/mqtt/username";
    mqttPasswordSecret = "home-assistant/mqtt/password";
    scriptPackages = with pkgs; [
      jq
      rbw
    ];
  };
}
