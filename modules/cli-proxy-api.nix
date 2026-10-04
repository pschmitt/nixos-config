{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.cli-proxy-api;
in
{
  options.services.cli-proxy-api = {
    enable = lib.mkEnableOption "CLIProxyAPI subscription gateway";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llm-agents.cli-proxy-api;
      description = "CLIProxyAPI package to run.";
    };

    configFile = lib.mkOption {
      type = lib.types.str;
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
