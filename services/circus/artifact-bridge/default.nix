{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.circus.stricknaniArtifactBridge;
  circus = config.services.circus;
  secret = name: config.sops.secrets."circus/${name}".path;
  niks3 =
    inputs.nixos-config-private.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bridge = pkgs.writers.writePython3Bin "circus-stricknani-artifact-bridge" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./bridge.py);
in
{
  options.services.circus.stricknaniArtifactBridge.enable =
    lib.mkEnableOption "publishing Stricknani Circus outputs to Niks3";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          circus.enable && circus.effects.enable && circus.githubApp.enable && circus.rworkerPool.enable;
        message = "The Stricknani artifact bridge requires Circus, its effects, GitHub App, and read-only API key.";
      }
    ];

    sops.secrets."circus/effects-secrets".restartUnits = lib.mkAfter [
      "circus-stricknani-artifact-bridge.service"
    ];

    users.users.circus-stricknani-bridge = {
      isSystemUser = true;
      group = "circus-stricknani-bridge";
    };
    users.groups.circus-stricknani-bridge = { };

    systemd.services.circus-stricknani-artifact-bridge = {
      description = "Publish Stricknani Circus artifacts to Niks3";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "circus-server.service"
      ];
      wants = [ "network-online.target" ];
      path = [
        config.nix.package
        niks3
        pkgs.gitMinimal
      ];
      serviceConfig = {
        User = "circus-stricknani-bridge";
        Group = "circus-stricknani-bridge";
        SupplementaryGroups = [ "circus-github-token" ];
        StateDirectory = "circus-stricknani-bridge";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "circus-stricknani-bridge";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        LoadCredential = [
          "api:${secret "autoscaler-api-key"}"
          "secrets:${secret "effects-secrets"}"
        ];
        ExecStart = lib.escapeShellArgs [
          (lib.getExe bridge)
          "--api"
          "http://127.0.0.1:${toString circus.settings.server.port}"
          "--api-token-file"
          "%d/api"
          "--github-token-file"
          "/run/circus-github-token/token"
          "--secrets-file"
          "%d/secrets"
          "--state-dir"
          "/var/lib/circus-stricknani-bridge"
          "--runtime-dir"
          "/run/circus-stricknani-bridge"
        ];
        Restart = "always";
        RestartSec = 10;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
