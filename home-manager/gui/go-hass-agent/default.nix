{
  config,
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
      # obs-control backs the mic-mute and roomba-overlay buttons (enableWorkCommands);
      # ms-teams backs the teams/online-meeting sensors; python3+dbus-python backs
      # the gnome-keyring status sensor (single-process OpenSession + Locked reads).
      services.go-hass-agent.scriptPackages =
        with pkgs;
        [
          grim
          jq
          (python3.withPackages (ps: [ ps.dbus-python ]))
          timew-status
        ]
        ++ lib.optionals config.services.go-hass-agent.enableWorkCommands [
          obs-control
          ms-teams
        ];

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
        ++ lib.optionals config.services.go-hass-agent.enableWorkstationCommands [
          {
            name = "Pause Media Playback";
            exec = "${commandScripts."playerctl-pause.sh"}";
            icon = "mdi:pause";
          }
          {
            name = "Resume Media Playback";
            exec = "${commandScripts."playerctl-play.sh"}";
            icon = "mdi:play";
          }
        ]
        ++ lib.optionals config.services.go-hass-agent.enableWorkCommands [
          {
            name = "Connect Bluetooth Headset";
            exec = "${commandScripts."bluetooth-headset-connect.sh"}";
            icon = "mdi:headset";
          }
          {
            name = "Timewarrior Start";
            exec = "${commandScripts."timewarrior-start.sh"}";
            icon = "mdi:briefcase";
          }
          {
            name = "Timewarrior Stop";
            exec = "${commandScripts."timewarrior-stop.sh"}";
            icon = "mdi:briefcase-off";
          }
          {
            name = "Feierabend Start";
            exec = "${commandScripts."feierabend-start.sh"}";
            icon = "mdi:beer";
          }
          {
            name = "Feierabend Stop";
            exec = "${commandScripts."feierabend-stop.sh"}";
            icon = "mdi:beer-off";
          }
          {
            name = "Stop WIIT VPN";
            exec = "${commandScripts."stop-gec-vpn.sh"}";
            icon = "mdi:vpn";
          }
          {
            name = "Unlock GNOME Keyring";
            exec = "${commandScripts."gnome-keyring-unlock.sh"}";
            icon = "mdi:key-chain-variant";
          }
          {
            name = "OBS Show Roomba";
            exec = "${commandScripts."obs-show-roomba.sh"}";
            icon = "mdi:robot-vacuum";
          }
          {
            name = "OBS Hide Roomba";
            exec = "${commandScripts."obs-hide-roomba.sh"}";
            icon = "mdi:robot-vacuum";
          }
        ];
      }
      // lib.optionalAttrs config.services.go-hass-agent.enableWorkCommands {
        switch = [
          {
            name = "Microphone Mute";
            exec = "${commandScripts."obs-mute-switch.sh"}";
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

    (lib.mkIf config.services.go-hass-agent.enableWorkCommands {
      services.go-hass-agent.obsPasswordSecret = lib.mkDefault "obs/websocket/password";

      # obs-control on PATH for the hyprland keybinds and waybar mic toggle;
      # ms-teams for the ms-teams-join-room keybind script (the go-hass-agent
      # buttons/sensors reach them via scriptPackages above).
      home.packages = [
        pkgs.obs-control
        pkgs.ms-teams
      ];

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
