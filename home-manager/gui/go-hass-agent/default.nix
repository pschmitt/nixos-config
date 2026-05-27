{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.go-hass-agent;

  mkRegularFiles =
    prefix: dir:
    let
      files = lib.filterAttrs (_: type: type == "regular") (builtins.readDir dir);
      mkFile = name: {
        name = "${prefix}/${name}";
        value = {
          source = dir + "/${name}";
          executable = true;
        };
      };
    in
    lib.listToAttrs (map mkFile (builtins.attrNames files));

  mkNamedFilesNoExec =
    prefix: dir: names:
    lib.listToAttrs (
      map (name: {
        name = "${prefix}/${name}";
        value = {
          source = dir + "/${name}";
        };
      }) names
    );
in
{
  options.services.go-hass-agent = {
    enable = lib.mkEnableOption "go-hass-agent user service";

    tokenSecret = lib.mkOption {
      type = lib.types.str;
      default = "home-assistant/mcp/token";
      description = "SOPS secret name for the Home Assistant token.";
    };

    mqttUsernameSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SOPS secret name for the MQTT username.";
    };

    mqttPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SOPS secret name for the MQTT password.";
    };
  };

  config = lib.mkMerge [
    {
      xdg.configFile = lib.mkMerge [
        (mkRegularFiles "go-hass-agent/scripts" ./scripts)
        (mkRegularFiles "go-hass-agent/commands" ./commands)
        (mkNamedFilesNoExec "go-hass-agent" ./. [
          "commands.toml"
          "delete-device.sh"
          "re-register.sh"
        ])
      ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = (cfg.mqttUsernameSecret == null) == (cfg.mqttPasswordSecret == null);
          message = "services.go-hass-agent MQTT username/password secrets must either both be set or both be null.";
        }
      ];

      home.packages = [
        pkgs.go-hass-agent
      ];

      sops.secrets = {
        "home-assistant/server".mode = lib.mkDefault "0400";
        "${cfg.tokenSecret}".mode = lib.mkDefault "0400";
        "home-assistant/mqtt/host".mode = lib.mkDefault "0400";
      }
      // lib.optionalAttrs (cfg.mqttUsernameSecret != null) {
        "${cfg.mqttUsernameSecret}".mode = lib.mkDefault "0400";
      }
      // lib.optionalAttrs (cfg.mqttPasswordSecret != null) {
        "${cfg.mqttPasswordSecret}".mode = lib.mkDefault "0400";
      };

      sops.templates."go-hass-agent.env" = {
        mode = "0400";
        content = ''
          GOHASSAGENT_LOGLEVEL=debug
          HASS_SERVER=${builtins.getAttr "home-assistant/server" config.sops.placeholder}
          HASS_TOKEN=${builtins.getAttr cfg.tokenSecret config.sops.placeholder}
          MQTT_SERVER=${builtins.getAttr "home-assistant/mqtt/host" config.sops.placeholder}
        ''
        + lib.optionalString (cfg.mqttUsernameSecret != null) ''
          MQTT_USERNAME=${builtins.getAttr cfg.mqttUsernameSecret config.sops.placeholder}
        ''
        + lib.optionalString (cfg.mqttPasswordSecret != null) ''
          MQTT_PASSWORD=${builtins.getAttr cfg.mqttPasswordSecret config.sops.placeholder}
        '';
      };

      systemd.user.services.go-hass-agent = {
        Unit = {
          Description = "Go Hass Agent";
          After = [
            "network.target"
            "sops-nix.service"
          ];
          Wants = [ "sops-nix.service" ];
        };

        Service =
          let
            goHassAgent = "${pkgs.go-hass-agent}/bin/go-hass-agent";
            mqttConfigArgs = lib.concatStringsSep " " (
              [
                "--mqtt-server=$MQTT_SERVER"
                "--mqtt-topic-prefix=homeassistant"
              ]
              ++ lib.optional (cfg.mqttUsernameSecret != null) "--mqtt-user=$MQTT_USERNAME"
              ++ lib.optional (cfg.mqttPasswordSecret != null) "--mqtt-password=$MQTT_PASSWORD"
            );
          in
          {
            EnvironmentFile = config.sops.templates."go-hass-agent.env".path;
            Environment = [
              "XDG_RUNTIME_DIR=/run/user/%U"
              "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
            ];
            ExecStartPre = [
              "${pkgs.bash}/bin/bash -c '${goHassAgent} register --server=$HASS_SERVER --token=$HASS_TOKEN'"
              "${pkgs.bash}/bin/bash -c '${goHassAgent} config ${mqttConfigArgs}'"
            ];
            ExecStart = "${goHassAgent} run";
            Restart = "always";
            RestartSec = "5";
          };

        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
