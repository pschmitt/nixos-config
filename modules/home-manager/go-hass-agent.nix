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
    "playerctl.sh"
    "screencast.sh"
  ];

  mkRegularFiles =
    prefix: dir:
    let
      files = lib.filterAttrs (_: type: type == "regular") (builtins.readDir dir);
      selectedFiles = lib.filterAttrs (
        name: _:
        # lib.sh is sourced by the other scripts and must not be installed as
        # an executable script sensor (go-hass-agent would try to schedule it)
        name != "lib.sh"
        && (
          prefix != "go-hass-agent/scripts"
          || cfg.enableDesktopScripts
          || !(builtins.elem name desktopScriptNames)
        )
      ) files;
      mkFile = name: {
        name = "${prefix}/${name}";
        value = {
          # NOTE Interpolating the whole directory (instead of the single
          # file) keeps sibling files like lib.sh next to the script in the
          # nix store, so relative source statements keep working.
          source = pkgs.writeShellScript name ''
            export PATH="${lib.makeBinPath cfg.scriptPackages}:${config.home.profileDirectory}/bin:${config.home.homeDirectory}/.local/bin:$PATH"
            exec ${pkgs.bash}/bin/bash ${dir}/${name} "$@"
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

    disabledSensors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # abrt does not exist on NixOS
        "sensors.system.abrt_problems"
        # chronyc is not in the service PATH (and chrony is usually not
        # running anyway)
        "sensors.system.chrony"
        # smartctl requires cap_sys_rawio, which a user service cannot get
        "sensors.disk.smart"
        # getMountInfo requires root
        "sensors.disk.usage"

        # Stuff we do not care about
        "sensors.agent.version"
        "sensors.batteries"
        "sensors.cpu.frequencies"
        "sensors.cpu.usage"
        "sensors.desktop.app_sensors"
        "sensors.desktop.desktop_settings_sensors"
        "sensors.disk.rates"
        "sensors.location"
        # NOTE sensors.media.audio must stay enabled: the MQTT volume/mute
        # controls are fed by the audio worker and the agent panics in
        # NumberEntity.MarshalConfig when it is disabled
        "sensors.media.microphone_in_use"
        "sensors.memory.oom_events"
        "sensors.network.connections"
        "sensors.network.links"
        "sensors.network.usage"
        "sensors.power.screen_lock"
      ];
      description = ''
        Sensor worker preference paths (TOML, dot-separated) that get disabled
        in preferences.toml before the agent starts.
        This is fully declarative: every disabled flag in preferences.toml is
        set to true when its path is listed here and back to false otherwise,
        so removing an entry re-enables the sensor again.
        NOTE Home Assistant keeps the entities of newly disabled sensors
        around as unavailable. Set force = true once (or run
        go-hass-agent-reregister) to clean them up.
      '';
    };

    force = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Force (re-)registration with Home Assistant on every service start.
        Enable this temporarily after changing disabledSensors to refresh the
        registration. For a full cleanup of stale entities, run
        go-hass-agent-reregister instead.
      '';
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
        (pkgs.writeShellApplication {
          name = "go-hass-agent-reregister";
          runtimeInputs = [
            pkgs.curl
            pkgs.go-hass-agent
            pkgs.jq
            pkgs.websocat
            # provides tomlq, for the preferences.toml fallback
            pkgs.yq
          ];
          text = ''
            export GO_HASS_AGENT_ENV_FILE=${lib.escapeShellArg config.sops.templates."go-hass-agent.env".path}
          ''
          + builtins.readFile (root + "/go-hass-agent-reregister.sh");
        })
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
            # NOTE preferences.toml is mutable agent state, so we patch the
            # worker toggles in place instead of managing the whole file.
            # Every disabled flag is set declaratively: true when listed in
            # cfg.disabledSensors, false otherwise.
            disableSensors = pkgs.writeShellScript "go-hass-agent-disable-sensors" ''
              PREFS="''${XDG_CONFIG_HOME:-$HOME/.config}/go-hass-agent/preferences.toml"

              if [[ ! -f "$PREFS" ]]
              then
                echo "$PREFS does not exist (yet?), skipping sensor disabling" >&2
                exit 0
              fi

              ${pkgs.yq}/bin/tomlq --toml-output --in-place \
                --argjson managed ${lib.escapeShellArg (builtins.toJSON cfg.disabledSensors)} '
                  reduce (paths | select(.[-1] == "disabled")) as $p (.;
                    setpath($p; ($p[:-1] | join(".")) as $key
                      | $managed | index($key) != null)
                  )
                ' "$PREFS"
            '';
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
              "${pkgs.bash}/bin/bash -c '${goHassAgent} register ${lib.optionalString cfg.force "--force --ignore-hass-urls "}--server=$HASS_SERVER --token=$HASS_TOKEN'"
              "${pkgs.bash}/bin/bash -c '${goHassAgent} config ${mqttConfigArgs}'"
              "${disableSensors}"
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
