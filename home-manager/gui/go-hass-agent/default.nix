{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services.go-hass-agent) commandScripts;
in
{
  imports = [ ../../../modules/home-manager/go-hass-agent.nix ];

  config = lib.mkMerge [
    {
      # timew-status provides timew-is-on/timew-total for the timewarrior sensors;
      # obs-control backs the OBS button commands.
      services.go-hass-agent.scriptPackages =
        with pkgs;
        [
          grim
          jq
          timew-status
        ]
        ++ lib.optional (hostname == "ge2") obs-control;

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
        ++ lib.optionals (hostname == "ge2") [
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

    {
      services.go-hass-agent = {
        enable = lib.mkDefault true;
        mqttUsernameSecret = lib.mkDefault "home-assistant/mqtt/username";
        mqttPasswordSecret = lib.mkDefault "home-assistant/mqtt/password";
      };

      # The MQTT credentials are host-specific
      sops.secrets = lib.mkIf config.services.go-hass-agent.enable {
        "home-assistant/mqtt/username".sopsFile = config.host.sopsFile;
        "home-assistant/mqtt/password".sopsFile = config.host.sopsFile;
      };
    }

    (lib.mkIf (hostname == "ge2") {
      services.go-hass-agent.obsPasswordSecret = lib.mkDefault "obs/websocket/password";

      # obs-control on PATH for the hyprland keybinds and waybar mic toggle
      # (the go-hass-agent buttons reach it via scriptPackages above).
      home.packages = [ pkgs.obs-control ];

      sops.secrets = lib.mkIf config.services.go-hass-agent.enable {
        # Rendered to the canonical obs-websocket password path so obs-control
        # can read it outside the go-hass-agent service env (keybinds/waybar).
        "obs/websocket/password" = {
          sopsFile = config.host.sopsFile;
          path = "${config.xdg.configHome}/obs-studio/obs-websocket.password";
        };
      };
    })
  ];
}
