{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cli-proxy-api;
  yaml = pkgs.formats.yaml { };

  authCheck = pkgs.writeShellApplication {
    name = "cli-proxy-api-auth-check";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/cli-proxy-api-auth-check.sh;
  };
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI subscription gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llm-agents.cli-proxy-api;
      description = "CLIProxyAPI package to run.";
    };

    settings = lib.mkOption {
      inherit (yaml) type;
      default = { };
      description = "Non-secret CLIProxyAPI configuration. Keep credentials in a runtime configFile.";
    };

    modelPools = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      description = ''
        Named model pools, mapping OAuth providers to upstream model IDs.
        Each pool becomes a shared alias while preserving original model names.
        These select routes; they do not restrict a client's access to other models.
      '';
    };

    modelPoolsHideOriginals = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        claude-sonnet = [ "antigravity" ];
      };
      description = ''
        Per pool, the providers whose upstream model name is replaced by the
        pool alias instead of being listed next to it. Providers not named
        here keep their original model name.
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.str;
      default = toString (yaml.generate "cli-proxy-api.yaml" cfg.settings);
      description = ''
        Runtime YAML configuration, including client authentication keys.
        Supply a secret path or SOPS template; never put credentials in the Nix store.
      '';
    };

    managementKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Runtime file holding the management key. When set, a Monit check
        alerts if an enabled account needs a new login or has another
        authentication problem.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/cli-proxy-api";
      description = "Persistent directory for OAuth credentials and runtime state.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.cli-proxy-api.settings = {
      config-version = lib.mkDefault 8;
      server.host = lib.mkDefault "127.0.0.1";
      oauth = {
        auth-dir = lib.mkDefault "${cfg.dataDir}/auth";
        model-alias = lib.mkIf (cfg.modelPools != { }) (
          lib.foldlAttrs (
            aliases: pool: providers:
            lib.foldlAttrs (
              acc: provider: name:
              acc
              // {
                ${provider} = (acc.${provider} or [ ]) ++ [
                  {
                    inherit name;
                    alias = pool;
                    fork = !(lib.elem provider (cfg.modelPoolsHideOriginals.${pool} or [ ]));
                  }
                ];
              }
            ) aliases providers
          ) { } cfg.modelPools
        );
      };
    };

    environment.systemPackages = [ cfg.package ];

    services.monit.checks.cli-proxy-api-auth = lib.mkIf (cfg.managementKeyFile != null) {
      type = "program";
      path = lib.concatStringsSep " " [
        (lib.getExe authCheck)
        "http://127.0.0.1:${toString (cfg.settings.server.port or 8317)}"
        cfg.managementKeyFile
      ];
      group = "cli-proxy-api";
      every = 5;
      conditions = "if status != 0 then alert";
    };

    users = {
      users.cli-proxy-api = {
        isSystemUser = true;
        group = "cli-proxy-api";
        home = cfg.dataDir;
      };
      groups.cli-proxy-api = { };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 cli-proxy-api cli-proxy-api -"
      "d ${cfg.dataDir}/auth 0700 cli-proxy-api cli-proxy-api -"
    ];

    systemd.services.cli-proxy-api = {
      description = "CLIProxyAPI subscription gateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      unitConfig.RequiresMountsFor = cfg.dataDir;
      environment.HOME = cfg.dataDir;
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} -config ${lib.escapeShellArg cfg.configFile}";
        User = "cli-proxy-api";
        Group = "cli-proxy-api";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        CapabilityBoundingSet = "";
      };
    };
  };
}
