{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.lnxlink;
  scriptsDir = ../../home-manager/cli/lnxlink/scripts;

  nixConfigJson = builtins.toJSON {
    inherit (cfg) modules exclude;
    update_interval = cfg.updateInterval;
    update_on_change = cfg.updateOnChange;
    bash_expose = cfg.bashExpose;
  };

  nixConfigUpdaterPy = pkgs.writeText "lnxlink-update-nix-config.py" ''
    import sys, json, yaml

    config_path, nix_config_str = sys.argv[1], sys.argv[2]
    nix = json.loads(nix_config_str)

    with open(config_path) as f:
        config = yaml.safe_load(f) or {}

    for key in ('modules', 'exclude', 'update_interval', 'update_on_change'):
        val = nix.get(key)
        config[key] = val if val else None

    config.setdefault('settings', {}).setdefault('bash', {})['expose'] = \
        nix.get('bash_expose', [])

    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
  '';

  updateNixConfig = pkgs.writeShellScript "lnxlink-update-nix-config" ''
    exec ${pkgs.python3.withPackages (p: [ p.pyyaml ])}/bin/python3 \
      ${nixConfigUpdaterPy} "$@"
  '';

  mkScriptFiles =
    dir:
    let
      files = lib.filterAttrs (_: type: type == "regular") (builtins.readDir dir);
      mkFile = name: {
        name = "lnxlink/scripts/${name}";
        value = {
          source = pkgs.writeShellScript name ''
            export PATH="${lib.makeBinPath cfg.scriptPackages}:${config.home.profileDirectory}/bin:${config.home.homeDirectory}/.local/bin:$PATH"
            exec ${pkgs.bash}/bin/bash ${dir + "/${name}"} "$@"
          '';
          executable = true;
        };
      };
    in
    lib.listToAttrs (map mkFile (builtins.attrNames files));

  initialConfig = pkgs.writeText "lnxlink-initial.yaml" (
    ''
      mqtt:
        transport: "mqtt"
        prefix: 'lnxlink'
        clientId: 'lnxlink'
        server: '192.168.1.1'
        port: 1883
        auth:
          user: 'user'
          pass: 'pass'
          tls: false
          keyfile: ""
          certfile: ""
          ca_certs: ""
        discovery:
          enabled: true
          prefix: "homeassistant"
        lwt:
          enabled: true
          qos: 1
        clear_on_off: true
        homeassistant:
          url: ""
          token: ""
          token_env: ""
          token_file: ""
          timeout: 20
          verify_ssl: true
          subscribe_commands: true
      update_interval: ${toString cfg.updateInterval}
      update_on_change: ${if cfg.updateOnChange then "true" else "false"}
      modules:
    ''
    + lib.optionalString (cfg.modules != [ ]) (lib.concatMapStrings (m: "  - ${m}\n") cfg.modules)
    + ''
      custom_modules:
      exclude:
    ''
    + lib.optionalString (cfg.exclude != [ ]) (lib.concatMapStrings (m: "  - ${m}\n") cfg.exclude)
    + ''
      settings:
        statistics: "https://analyzer.bkbilly.workers.dev"
    ''
  );
in
{
  options.services.lnxlink = {
    enable = lib.mkEnableOption "lnxlink Home Assistant MQTT integration";

    mqttHostSecret = lib.mkOption {
      type = lib.types.str;
      default = "home-assistant/mqtt/host";
      description = "SOPS secret name for the MQTT broker hostname.";
    };

    mqttUsernameSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SOPS secret name for the MQTT username. Must be paired with mqttPasswordSecret.";
    };

    mqttPasswordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "SOPS secret name for the MQTT password. Must be paired with mqttUsernameSecret.";
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "lnxlink";
      description = "MQTT topic prefix.";
    };

    clientId = lib.mkOption {
      type = lib.types.str;
      default = config.home.username;
      description = "MQTT client identifier, used as the device name in Home Assistant.";
    };

    mqttPort = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT broker port.";
    };

    modules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Modules to load. Empty list auto-loads all modules not in exclude.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Modules to exclude from auto-loading.";
    };

    updateInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Sensor refresh rate in seconds.";
    };

    updateOnChange = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Send updates only when values change rather than on every interval tick.";
    };

    scriptPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages whose bin directories are injected into PATH for bash module scripts.";
    };

    bashExpose = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Entries for settings.bash.expose in lnxlink.yaml (custom sensors via shell scripts).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.mqttUsernameSecret == null) == (cfg.mqttPasswordSecret == null);
        message = "services.lnxlink: mqttUsernameSecret and mqttPasswordSecret must either both be set or both be null.";
      }
    ];

    home.packages = [ pkgs.lnxlink ];

    sops.secrets = {
      "${cfg.mqttHostSecret}".mode = lib.mkDefault "0400";
    }
    // lib.optionalAttrs (cfg.mqttUsernameSecret != null) {
      "${cfg.mqttUsernameSecret}".mode = lib.mkDefault "0400";
    }
    // lib.optionalAttrs (cfg.mqttPasswordSecret != null) {
      "${cfg.mqttPasswordSecret}".mode = lib.mkDefault "0400";
    };

    sops.templates."lnxlink.env" = {
      mode = "0400";
      content =
        "LNXLINK_MQTT_SERVER=${builtins.getAttr cfg.mqttHostSecret config.sops.placeholder}\n"
        + lib.optionalString (
          cfg.mqttUsernameSecret != null
        ) "LNXLINK_MQTT_USER=${builtins.getAttr cfg.mqttUsernameSecret config.sops.placeholder}\n"
        + lib.optionalString (
          cfg.mqttPasswordSecret != null
        ) "LNXLINK_MQTT_PASS=${builtins.getAttr cfg.mqttPasswordSecret config.sops.placeholder}\n";
    };

    xdg.configFile = mkScriptFiles scriptsDir;

    home.activation.lnxlink-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      lnxlink_config_dir="${config.xdg.configHome}/lnxlink"
      lnxlink_config_file="$lnxlink_config_dir/lnxlink.yaml"
      nix_hash_file="$lnxlink_config_dir/.nix-config.sha256"

      if [[ ! -f "$lnxlink_config_file" ]]
      then
        $DRY_RUN_CMD mkdir -p "$lnxlink_config_dir"
        $DRY_RUN_CMD install -m600 "${initialConfig}" "$lnxlink_config_file"
      fi

      if [[ "$(cat "$nix_hash_file" 2>/dev/null)" != "${builtins.hashString "sha256" nixConfigJson}" ]]
      then
        $DRY_RUN_CMD ${updateNixConfig} \
          "$lnxlink_config_file" \
          ${lib.escapeShellArg nixConfigJson}
        if [[ -z "''${DRY_RUN_CMD:-}" ]]
        then
          printf '%s' "${builtins.hashString "sha256" nixConfigJson}" > "$nix_hash_file"
        fi
      fi
    '';

    systemd.user.services.lnxlink = {
      Unit = {
        Description = "LNXlink Home Assistant MQTT integration";
        After = [
          "network.target"
          "sops-nix.service"
        ];
        Wants = [ "sops-nix.service" ];
      };

      Service = {
        EnvironmentFile = config.sops.templates."lnxlink.env".path;
        Environment = [
          "LNXLINK_MQTT_PREFIX=${cfg.prefix}"
          "LNXLINK_MQTT_CLIENTID=${cfg.clientId}"
          "LNXLINK_MQTT_PORT=${toString cfg.mqttPort}"
        ];
        ExecStart = pkgs.writeShellScript "lnxlink-start" ''
          server="$LNXLINK_MQTT_SERVER"
          server="''${server#*://}"
          server="''${server%%:*}"
          export LNXLINK_MQTT_SERVER="$server"
          exec ${pkgs.lnxlink}/bin/lnxlink \
            -c ${config.xdg.configHome}/lnxlink/lnxlink.yaml -i
        '';
        Restart = "always";
        RestartSec = "5";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
