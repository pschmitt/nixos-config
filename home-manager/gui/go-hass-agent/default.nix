# NOTE osConfig is only set when home-manager runs as a NixOS module. On
# standalone home-manager hosts (eg. fnuc) it defaults to null and the service
# must be enabled and wired up manually.
{
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  inherit (config.services.go-hass-agent) commandScripts;
in
{
  imports = [ ../../../modules/home-manager/go-hass-agent.nix ];

  config = lib.mkMerge [
    {
      services.go-hass-agent.commands = {
        button = [
          {
            name = "Take Screenshot";
            exec = "${commandScripts."screenshot.sh"}";
            icon = "mdi:camera";
          }
          {
            name = "Unlock Hyprlock";
            exec = "${commandScripts."unlock-hyprlock.sh"}";
            icon = "mdi:lock-open-variant";
          }
        ]
        ++ lib.optionals (osConfig != null && osConfig.networking.hostName == "ge2") [
          {
            name = "OBS BRB";
            exec = "${commandScripts."obs-brb.sh"}";
            icon = "mdi:smoking";
          }
          {
            name = "OBS Webcam";
            exec = "${commandScripts."obs-webcam.sh"}";
            icon = "mdi:webcam";
          }
          {
            name = "OBS Alternative Camera";
            exec = "${commandScripts."obs-alt-camera.sh"}";
            icon = "mdi:camera-flip";
          }
          {
            name = "Mute Microphone";
            exec = "${commandScripts."obs-mute.sh"}";
            icon = "mdi:microphone-off";
          }
          {
            name = "Unmute Microphone";
            exec = "${commandScripts."obs-unmute.sh"}";
            icon = "mdi:microphone";
          }
        ];
      };
    }

    (lib.mkIf (osConfig != null) {
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
    })

    (lib.mkIf (osConfig != null && osConfig.networking.hostName == "ge2") {
      services.go-hass-agent.obsPasswordSecret = lib.mkDefault "obs/websocket/password";

      sops.secrets = lib.mkIf config.services.go-hass-agent.enable {
        "obs/websocket/password".sopsFile = osConfig.custom.sopsFile;
      };
    })
  ];
}
