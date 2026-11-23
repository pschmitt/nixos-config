{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.circus;
  scheduler = pkgs.writers.writePython3Bin "circus-consumer-builds" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./consumer_builds.py);
in
{
  options.services.circus.consumerBuildRepositories = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Trusted GitHub repositories whose flake declarations Circus schedules against nixos-config.";
  };

  config = lib.mkIf (cfg.enable && cfg.consumerBuildRepositories != [ ]) {
    systemd.services.circus-consumer-builds = {
      description = "Schedule Circus packages for consumer flake pins";
      after = [
        "network-online.target"
        "circus-server.service"
      ];
      wants = [ "network-online.target" ];
      path = [
        config.nix.package
        pkgs.gitMinimal
      ];
      environment.XDG_CACHE_HOME = "/var/cache/circus-consumer-builds";
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        CacheDirectory = "circus-consumer-builds";
        StateDirectory = "circus-consumer-builds";
        LoadCredential = [ "api:${config.sops.secrets."circus/admin-api-key".path}" ];
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe scheduler)
            "--api"
            "http://127.0.0.1:${toString cfg.settings.server.port}"
            "--api-token-file"
            "%d/api"
            "--state-dir"
            "/var/lib/circus-consumer-builds"
          ]
          ++ lib.concatMap (repository: [
            "--repository"
            repository
          ]) cfg.consumerBuildRepositories
        );
      };
    };

    systemd.timers.circus-consumer-builds = {
      description = "Check producer revisions and consumer pins for Circus";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitInactiveSec = "5min";
      };
    };
  };
}
