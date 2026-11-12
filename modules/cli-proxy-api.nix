{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cli-proxy-api;
  yaml = pkgs.formats.yaml { };
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

    configFile = lib.mkOption {
      type = lib.types.str;
      default = toString (yaml.generate "cli-proxy-api.yaml" cfg.settings);
      description = ''
        Runtime YAML configuration, including client authentication keys.
        Supply a secret path or SOPS template; never put credentials in the Nix store.
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
                    fork = true;
                  }
                ];
              }
            ) aliases providers
          ) { } cfg.modelPools
        );
      };
    };

    environment.systemPackages = [ cfg.package ];

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
