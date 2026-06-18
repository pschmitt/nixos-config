{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.go-hass-agent;
  tomlFormat = pkgs.formats.toml { };
  scriptLib = import ./script-lib.nix { inherit lib pkgs; };
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

  # Runtime PATH for wrapped scripts: script packages + the user profile and
  # personal bin dirs.
  scriptPath = [
    "${config.home.profileDirectory}/bin"
    "${config.home.homeDirectory}/bin"
    "${config.home.homeDirectory}/.local/bin"
  ];

  wrapScripts =
    dir: filter:
    scriptLib.wrapDir {
      inherit dir filter;
      runtimeInputs = cfg.scriptPackages;
      extraPath = scriptPath;
    };

  # lib.sh is sourced by the other scripts and must not be installed as an
  # executable script sensor (go-hass-agent would try to schedule it).
  sensorScripts = wrapScripts (root + "/scripts") (
    name: name != "lib.sh" && (cfg.enableDesktopScripts || !(builtins.elem name desktopScriptNames))
  );
  commandScripts = wrapScripts (root + "/commands") (name: name != "lib.sh");
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

    obsPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SOPS secret name for the OBS websocket password.";
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
        # Disable MQTT audio controls (mute switch + volume number) — we use
        # obs-mute-switch.sh (switch.ge2_microphone_mute) for mute instead
        "controls.media.audio"
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
      default = with pkgs; [
        grim
        jq
      ];
      description = "Packages whose bin directories are injected into wrapped go-hass-agent scripts and commands.";
    };

    enableDesktopScripts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install desktop-session specific go-hass-agent scripts.";
    };

    enableWorkstationCommands = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to expose workstation-oriented go-hass-agent command buttons such as media playback controls.";
    };

    enableWorkCommands = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to expose work-machine go-hass-agent buttons (Timewarrior, Feierabend, OBS audio, Bluetooth headset, GEC VPN, GNOME Keyring, OBS Roomba overlay).";
    };

    commandScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      readOnly = true;
      default = commandScripts;
      description = ''
        Wrapped command scripts (script file name -> nix store path), for
        referencing in the exec field of `commands` without relying on the
        ~/.config symlinks.
      '';
    };

    commands = lib.mkOption {
      inherit (tomlFormat) type;
      default = { };
      example = {
        button = [
          {
            name = "Take Screenshot";
            exec = "/path/to/screenshot.sh";
            icon = "mdi:camera";
          }
        ];
      };
      description = ''
        Contents of commands.toml, as a Nix attribute set. See
        <https://github.com/joshuar/go-hass-agent/blob/main/docs/agent/commands.md>
        for the schema (top-level button/switch/number lists).
      '';
    };
  };

  config = lib.mkMerge [
    {
      xdg.configFile = lib.mkMerge [
        (scriptLib.toFiles "go-hass-agent/scripts" sensorScripts)
        (scriptLib.toFiles "go-hass-agent/commands" commandScripts)
        (lib.mkIf (cfg.commands != { }) {
          "go-hass-agent/commands.toml".source =
            tomlFormat.generate "go-hass-agent-commands.toml" cfg.commands;
        })
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
      }
      // lib.optionalAttrs (cfg.obsPasswordSecret != null) {
        "${cfg.obsPasswordSecret}".mode = lib.mkDefault "0400";
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
        ''
        + lib.optionalString (cfg.obsPasswordSecret != null) ''
          OBS_API_PASSWORD=${builtins.getAttr cfg.obsPasswordSecret config.sops.placeholder}
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
