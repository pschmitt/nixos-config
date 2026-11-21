# Publish each artifact as it reaches the Circus cache. The publisher uses
# nixbot's effect sandbox and secrets.json and defaults to dry-run mode.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.circus.effects;
  circusCfg = config.services.circus;

  secret = name: config.sops.secrets."circus/${name}".path;

  nbo = inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system}.nixbot-cli;

  runner = pkgs.writers.writePython3Bin "circus-effects" {
    # Line length follows the repository's Python elsewhere (ruff, 120).
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./circus_effects.py);

  # The App installation token (../default.nix), for circus-effects/* statuses.
  githubTokenFile = "/run/circus-github-token/token";

  gitlabNixConf = config.sops.templates.nix-access-token-gitlab.path or null;
in
{
  options.services.circus.effects = {
    enable = lib.mkEnableOption "running the flake's effects after Circus builds";

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Only log which effects would run. Turn off together with nixbot's
        publish effects: two publishers race on the same destinations.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Loopback port the webhook listener binds.";
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "nixos-config";
      description = "Circus project whose evaluations may run effects.";
    };

    jobset = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Circus jobset whose evaluations may run effects.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch whose head commit may run effects.";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "pschmitt/nixos-config";
      description = "GitHub owner/repo of the flake (effects come from github:<repo>/<commit>).";
    };

    githubStatuses = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.dryRun && circusCfg.githubApp.enable;
      defaultText = lib.literalExpression "!dryRun && services.circus.githubApp.enable";
      description = "Report circus-effects/<name> commit statuses through the GitHub App.";
    };
  };

  config = lib.mkIf (circusCfg.enable && cfg.enable) {
    # Publish from the same signed outputs the Circus builders uploaded.
    nix.settings = {
      extra-substituters = [
        "http://127.0.0.1:${toString circusCfg.settings.server.port}/nix-cache/"
      ];
      extra-trusted-public-keys = [ circusCfg.settings.signing.public_key ];
    };

    sops.secrets = {
      # The effects' secrets.json, same shape as nixbot's per-repo file.
      "circus/effects-secrets" = config.sops.mkHostSecret { };
    };

    users = {
      groups.circus-effects-dashboard = { };
      users.circus-server.extraGroups = [ "circus-effects-dashboard" ];
      users.circus-effects = {
        isSystemUser = true;
        group = "circus-effects-dashboard";
        extraGroups = [ "circus-effects" ];
        home = "/var/lib/circus-effects";
      };
      groups.circus-effects = { };
    };

    systemd.services.circus-effects = {
      description = "Publish cached Circus build artifacts";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "circus-server.service"
      ];
      wants = [ "network-online.target" ];
      path = [
        config.nix.package
        nbo
        pkgs.bubblewrap
        pkgs.coreutils
        pkgs.gitMinimal
      ];
      environment = lib.optionalAttrs (gitlabNixConf != null) {
        # git.wiit.one flake inputs, like the Circus evaluator.
        NIX_USER_CONF_FILES = "%d/nix-gitlab";
      };
      serviceConfig = {
        User = "circus-effects";
        Group = "circus-effects-dashboard";
        # Private GitHub flake inputs (system token) and the App token.
        SupplementaryGroups = [
          "circus-effects"
          "nix-access-tokens"
        ]
        ++ lib.optional cfg.githubStatuses "circus-github-token";
        StateDirectory = "circus-effects";
        # The server can traverse this parent to reach public-status, but the
        # queue, done, changed, and lock subdirectories stay mode 0700.
        StateDirectoryMode = "0711";
        WorkingDirectory = "/var/lib/circus-effects";
        UMask = "0077";
        LoadCredential =
          lib.optional (!cfg.dryRun) "secrets:${secret "effects-secrets"}"
          ++ lib.optional (gitlabNixConf != null) "nix-gitlab:${gitlabNixConf}";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe runner)
            "--port"
            (toString cfg.port)
            "--state-dir"
            "/var/lib/circus-effects"
            "--cache-url"
            "http://127.0.0.1:${toString circusCfg.settings.server.port}/nix-cache/"
            "--project"
            cfg.project
            "--jobset"
            cfg.jobset
            "--branch"
            cfg.branch
            "--repository"
            cfg.repository
            "--nbo"
            (lib.getExe nbo)
            "--status-dir"
            "/var/lib/circus-effects/public-status"
          ]
          ++ lib.optionals (!cfg.dryRun) [
            "--run"
            "--secrets-file"
            "%d/secrets"
          ]
          ++ lib.optionals cfg.githubStatuses [
            "--status-token-file"
            githubTokenFile
          ]
        );
        Restart = "always";
        RestartSec = 10;
        # Evaluating the flake's effects (nbo effects list) needs memory.
        MemoryMax = "8G";
        # Effects run in bwrap sandboxes (user namespaces), so namespaces
        # stay allowed; the rest is locked down.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/circus-effects" ];
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
        ];
      };
    };

    services.monit.checks.circus-effects = {
      type = "host";
      address = "127.0.0.1";
      group = "services";
      restartUnit = "circus-effects";
      conditions = ''
        if failed port ${toString cfg.port} type tcp for 3 cycles then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
