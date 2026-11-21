# Effects for Circus (see README.md): circus-effects receives Circus'
# HMAC-signed evaluation_finished webhook (pschmitt/circus) on loopback, and
# for a green build of the branch's head runs the flake's push effects with
# nixbot's effect runner (`nbo effects run`: the same sandbox and secrets.json
# as nixbot). Dry-run by default: it only logs what it would publish.
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
      # HMAC key shared by Circus (signs) and circus-effects (verifies).
      "circus/effects-webhook-hmac" = config.sops.mkHostSecret { };
      # The effects' secrets.json, same shape as nixbot's per-repo file.
      "circus/effects-secrets" = config.sops.mkHostSecret { };
    };

    # Instance-level generic webhook: evaluation events only.
    services.circus.settings.notifications = {
      webhook_url = "http://127.0.0.1:${toString cfg.port}/hook";
      webhook_secret_file = secret "effects-webhook-hmac";
      webhook_build_events = false;
      webhook_evaluation_events = true;
    };

    users = {
      users.circus-effects = {
        isSystemUser = true;
        group = "circus-effects";
        home = "/var/lib/circus-effects";
      };
      groups.circus-effects = { };
    };

    systemd.services.circus-effects = {
      description = "Run flake effects after Circus evaluations";
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
        Group = "circus-effects";
        # Private GitHub flake inputs (system token) and the App token.
        SupplementaryGroups = [
          "nix-access-tokens"
        ]
        ++ lib.optional cfg.githubStatuses "circus-github-token";
        StateDirectory = "circus-effects";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/circus-effects";
        LoadCredential = [
          "hmac:${secret "effects-webhook-hmac"}"
        ]
        ++ lib.optional (!cfg.dryRun) "secrets:${secret "effects-secrets"}"
        ++ lib.optional (gitlabNixConf != null) "nix-gitlab:${gitlabNixConf}";
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe runner)
            "--port"
            (toString cfg.port)
            "--state-dir"
            "/var/lib/circus-effects"
            "--secret-file"
            "%d/hmac"
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
