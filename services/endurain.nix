{
  config,
  lib,
  pkgs,
  ...
}:
let
  endurainHost = "endurain.${config.domains.main}";
  endurainAliases = [
    "endurian.${config.domains.main}"
  ];
  endurainPort = 36387;
  endurainContainerPort = 8080;

  dataDir = "/srv/endurain";
  endurainDataDir = "${dataDir}/data/endurain/data";
  endurainLogsDir = "${dataDir}/data/endurain/logs";
  endurainPostgresDir = "${dataDir}/data/psql";
  endurainPgdataDir = "/var/lib/postgresql/data/pgdata";
  endurainUid = 1000;
  endurainGid = 1000;

  dbName = "endurain";
  dbUser = dbName;

  containerBackend = config.virtualisation.oci-containers.backend;
  endurainUnit = "${containerBackend}-endurain.service";
  postgresUnit = "${containerBackend}-endurain-postgres.service";

  networkName = "endurain";

  # renovate: datasource=docker depName=ghcr.io/endurain-project/endurain
  endurainVersion = "v0.17.3";

  runtimePkg =
    if containerBackend == "docker" then
      pkgs.docker
    else if containerBackend == "podman" then
      pkgs.podman
    else
      throw "Unsupported OCI container backend: ${containerBackend}";
  runtimeBin = "${runtimePkg}/bin/${containerBackend}";

  ensureNetworkScript = ''
    if ! ${runtimeBin} network inspect ${networkName} >/dev/null 2>&1
    then
      ${runtimeBin} network create ${networkName}
    fi
  '';
in
{
  sops = {
    secrets = {
      "endurain/env" = {
        inherit (config.custom) sopsFile;
        restartUnits = [
          endurainUnit
          postgresUnit
        ];
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${dataDir} 0750 root root - -"
      "d ${dataDir}/data 0750 root root - -"
      "d ${dataDir}/data/endurain 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainDataDir} 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainLogsDir} 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainPostgresDir} 0700 999 999 - -"
    ];

    services = {
      "${containerBackend}-endurain-postgres".preStart = ensureNetworkScript;
      "${containerBackend}-endurain".preStart = ensureNetworkScript;
    };
  };

  virtualisation.oci-containers.containers = {
    endurain-postgres = {
      image = "docker.io/postgres:17.5";
      autoStart = true;
      environment = {
        POSTGRES_DB = dbName;
        POSTGRES_USER = dbUser;
        PGDATA = endurainPgdataDir;
      };
      environmentFiles = [
        config.sops.secrets."endurain/env".path
      ];
      volumes = [
        "${endurainPostgresDir}:/var/lib/postgresql/data"
      ];
      networks = [ networkName ];
      extraOptions = [ "--network-alias=postgres" ];
    };

    endurain = {
      image = "ghcr.io/endurain-project/endurain:${endurainVersion}";
      pull = "always";
      autoStart = true;
      dependsOn = [ "endurain-postgres" ];
      environment = {
        ENDURAIN_HOST = "https://${endurainHost}";
        BEHIND_PROXY = "true";
        TZ = config.time.timeZone;
        UID = toString endurainUid;
        GID = toString endurainGid;

        POSTGRES_DB = dbName;
        POSTGRES_USER = dbUser;
        POSTGRES_HOST = "endurain-postgres";
        POSTGRES_PORT = "5432";

        REVERSE_GEO_PROVIDER = "geocode";
      };
      environmentFiles = [
        config.sops.secrets."endurain/env".path
      ];
      volumes = [
        "${endurainDataDir}:/app/backend/data"
        "${endurainLogsDir}:/app/backend/logs"
      ];
      ports = [
        "127.0.0.1:${toString endurainPort}:${toString endurainContainerPort}"
      ];
      networks = [ networkName ];
    };
  };

  services.nginx.virtualHosts."${endurainHost}" = {
    serverAliases = endurainAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString endurainPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "endurain" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${endurainUnit}"
      if failed
        port ${toString endurainPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
