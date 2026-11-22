{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  circus = config.services.circus;
  projects = lib.filter (name: circus.${"${name}ArtifactBridge"}.enable) [
    "circus"
    "declaroid"
    "monarch"
    "stricknani"
  ];
  secret = name: config.sops.secrets."circus/${name}".path;
  niks3 =
    inputs.nixos-config-private.inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bridge = pkgs.writers.writePython3Bin "circus-artifact-bridge" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./bridge.py);
in
{
  options.services.circus =
    lib.genAttrs
      [
        "circusArtifactBridge"
        "declaroidArtifactBridge"
        "monarchArtifactBridge"
        "stricknaniArtifactBridge"
      ]
      (name: {
        enable = lib.mkEnableOption "${name} Circus artifact publication to Niks3";
      });

  config = lib.mkIf (projects != [ ]) {
    assertions = [
      {
        assertion =
          circus.enable && circus.effects.enable && circus.githubApp.enable && circus.rworkerPool.enable;
        message = "The artifact bridge requires Circus, its effects, GitHub App, and read-only API key.";
      }
      {
        assertion =
          !(lib.any (name: builtins.elem name projects) [
            "declaroid"
            "stricknani"
          ])
          || circus.githubActionsAgents.pullRequestAuthorIdsFile != null;
        message = "The Stricknani artifact bridge requires the trusted PR author list.";
      }
    ];

    sops.secrets."circus/effects-secrets".restartUnits = lib.mkAfter (
      map (name: "circus-${name}-artifact-bridge.service") projects
    );
    sops.secrets."circus/pr-author-ids".restartUnits = lib.mkAfter (
      map (name: "circus-${name}-artifact-bridge.service") (
        lib.filter (name: builtins.elem name projects) [
          "declaroid"
          "stricknani"
        ]
      )
    );

    users.users = lib.genAttrs (map (name: "circus-${name}-bridge") projects) (name: {
      isSystemUser = true;
      group = name;
    });
    users.groups = lib.genAttrs (map (name: "circus-${name}-bridge") projects) (_: { });

    systemd.services = lib.listToAttrs (
      map (
        name:
        lib.nameValuePair "circus-${name}-artifact-bridge" {
          description = "Publish ${name} Circus artifacts to Niks3";
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
            User = "circus-${name}-bridge";
            Group = "circus-${name}-bridge";
            SupplementaryGroups = [ "circus-github-token" ];
            StateDirectory = "circus-${name}-bridge";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "circus-${name}-bridge";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            LoadCredential = [
              "api:${secret "autoscaler-api-key"}"
              "secrets:${secret "effects-secrets"}"
            ]
            ++ lib.optional (builtins.elem name [
              "declaroid"
              "stricknani"
            ]) "pr-authors:${toString circus.githubActionsAgents.pullRequestAuthorIdsFile}";
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe bridge)
                "--repository"
                "pschmitt/${name}"
                "--api"
                "http://127.0.0.1:${toString circus.settings.server.port}"
                "--api-token-file"
                "%d/api"
                "--github-token-file"
                "/run/circus-github-token/token"
                "--secrets-file"
                "%d/secrets"
                "--state-dir"
                "/var/lib/circus-${name}-bridge"
                "--runtime-dir"
                "/run/circus-${name}-bridge"
              ]
              ++
                lib.optionals
                  (builtins.elem name [
                    "declaroid"
                    "stricknani"
                  ])
                  [
                    "--pr-author-ids-file"
                    "%d/pr-authors"
                  ]
              ++ lib.optionals (name == "declaroid") [
                "--jobset"
                "main"
              ]
            );
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
        }
      ) projects
    );
  };
}
