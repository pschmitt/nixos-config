{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.go-hass-agent;
  root = ../../home-manager/gui/go-hass-agent;
  desktopScriptNames = [
    "desktop-clients.sh"
    "desktop-environment.sh"
    "gnome-keyring.sh"
    "lockscreen.sh"
    "monitors.sh"
    "ms-teams.sh"
    "obs.sh"
    "online-meeting.sh"
    "screencast.sh"
  ];

  mkRegularFiles =
    prefix: dir:
    let
      files = lib.filterAttrs (_: type: type == "regular") (builtins.readDir dir);
      selectedFiles =
        if prefix == "go-hass-agent/scripts" && !cfg.enableDesktopScripts then
          lib.filterAttrs (name: _: !(builtins.elem name desktopScriptNames)) files
        else
          files;
      mkFile = name: {
        name = "${prefix}/${name}";
        value = {
          source = pkgs.writeShellScript name ''
            export PATH="${lib.makeBinPath cfg.scriptPackages}:${config.home.profileDirectory}/bin:${config.home.homeDirectory}/.local/bin:$PATH"
            exec ${pkgs.bash}/bin/bash ${dir + "/${name}"} "$@"
          '';
          executable = true;
        };
      };
    in
    lib.listToAttrs (map mkFile (builtins.attrNames selectedFiles));

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

    scriptPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [ jq ];
      description = "Packages whose bin directories are injected into wrapped go-hass-agent scripts and commands.";
    };

    enableDesktopScripts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install desktop-session specific go-hass-agent scripts.";
    };
  };

  config = lib.mkMerge [
    {
      xdg.configFile = lib.mkMerge [
        (mkRegularFiles "go-hass-agent/scripts" (root + "/scripts"))
        (mkRegularFiles "go-hass-agent/commands" (root + "/commands"))
        (mkNamedFilesNoExec "go-hass-agent" root [
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
