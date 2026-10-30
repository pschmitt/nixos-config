{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.services.teams-live;

  jsonFormat = pkgs.formats.json { };

  effectiveSettings = lib.recursiveUpdate cfg.settings {
    browser_daemon = {
      url = lib.mkDefault cfg.browserDaemonUrl;
      profile = lib.mkDefault cfg.browserDaemonProfile;
      secret_file = lib.mkDefault (
        if cfg.browserDaemonSecretFile != null then cfg.browserDaemonSecretFile else null
      );
    };
    gitlab = {
      token_file = lib.mkDefault (if cfg.gitlabTokenFile != null then cfg.gitlabTokenFile else null);
    };
    teams = {
      credentials_file = lib.mkDefault (
        if cfg.credentialsFile != null then cfg.credentialsFile else null
      );
    };
  };

  defaultConfigFile = jsonFormat.generate "teams-live-config.json" effectiveSettings;
  configFile = if cfg.configFile != null then cfg.configFile else defaultConfigFile;
in
{
  options.services.teams-live = {
    enable = mkEnableOption "Microsoft Teams push watcher and GitLab MR integration";

    package = mkOption {
      type = types.package;
      default = pkgs.teams-live;
      description = "The teams-live package to run.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/teams-live";
      description = "Directory for state, token caches, and session credentials.";
    };

    user = mkOption {
      type = types.str;
      default = "teams-live";
      description = "User account under which teams-live runs.";
    };

    group = mkOption {
      type = types.str;
      default = "teams-live";
      description = "Group under which teams-live runs.";
    };

    extraGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra groups for the teams-live service.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to an explicit JSON/YAML configuration file. Overrides settings if provided.";
    };

    credentialsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a Teams session state or credentials JSON file (SOPS secret).";
    };

    gitlabTokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to the GitLab API token file (SOPS secret).";
    };

    browserDaemonUrl = mkOption {
      type = types.str;
      default = "";
      description = "Optional URL to browser-daemon node for automated re-authentication. Leave empty to disable.";
    };

    browserDaemonProfile = mkOption {
      type = types.str;
      default = "work";
      description = "Profile on the browser-daemon node with an active Teams session.";
    };

    browserDaemonSecretFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional path to the browser-daemon cluster secret (SOPS secret).";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = jsonFormat.type;
      };
      default = { };
      description = "Structured configuration for teams-live, serialized as JSON.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users = {
      users.${cfg.user} = {
        isSystemUser = true;
        inherit (cfg) group extraGroups;
        home = cfg.dataDir;
      };
      groups.${cfg.group} = { };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/state 0700 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/cache 0700 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/config 0700 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.teams-live = {
      description = "Microsoft Teams push watcher and GitLab MR integration";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        XDG_STATE_HOME = "${cfg.dataDir}/state";
        XDG_CACHE_HOME = "${cfg.dataDir}/cache";
        XDG_CONFIG_HOME = "${cfg.dataDir}/config";
        HOME = cfg.dataDir;
      };

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        SupplementaryGroups = cfg.extraGroups;
        WorkingDirectory = cfg.dataDir;
        ExecStart = "${lib.getExe cfg.package} --config ${configFile}";
        Restart = "always";
        RestartSec = "10s";

        # Security sandbox
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        ReadOnlyPaths =
          lib.optional (cfg.credentialsFile != null) cfg.credentialsFile
          ++ lib.optional (cfg.gitlabTokenFile != null) cfg.gitlabTokenFile
          ++ lib.optional (cfg.browserDaemonSecretFile != null) cfg.browserDaemonSecretFile;
        PrivateTmp = true;
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };
  };
}
