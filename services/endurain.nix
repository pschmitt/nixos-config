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

  # Gadgetbridge activity export from the phone, synced in via Syncthing and
  # consumed by the Endurain ingest watcher. Syncthing mirrors the whole tree
  # (gpx/, fit/, backups/, maps/, ...); the ingest watcher only globs flat
  # files in the dir it's pointed at (no recursion), so it's scoped to the
  # gpx/ subfolder specifically — Gadgetbridge's GPX auto-export directory.
  gadgetbridgeDir = "${dataDir}/gadgetbridge";
  gadgetbridgeGpxDir = "${gadgetbridgeDir}/gpx";
  gadgetbridgeSyncId = "6qqtd-3lljl";
  phoneDevices = [
    "zf10"
    "px5"
  ];

  ingestUser = "endurain-ingest";
  # Per-file processed markers (content-hash keyed). Lives OUTSIDE the synced
  # folder so the receive-only watch dir is never modified and re-syncs/reverts
  # cannot trigger duplicate uploads.
  ingestStateDir = "/var/lib/${ingestUser}";
  endurainIngest = pkgs.writeShellApplication {
    name = "endurain-ingest";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
    ];
    text = builtins.readFile ./endurain-ingest.sh;
  };
  endurainUid = 1000;
  endurainGid = 1000;

  dbName = "endurain";
  dbUser = dbName;

  containerBackend = config.virtualisation.oci-containers.backend;
  endurainUnit = "${containerBackend}-endurain.service";
  postgresUnit = "${containerBackend}-endurain-postgres.service";

  networkName = "endurain";

  # renovate: datasource=docker depName=ghcr.io/endurain-project/endurain
  endurainVersion = "v0.17.7";

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
      "endurain/env" = config.custom.mkSecret {
        restartUnits = [
          endurainUnit
          postgresUnit
        ];
      };
      # Endurain user login for the ingest service (username + password).
      "endurain-ingest/env" = config.custom.mkSecret {
        owner = ingestUser;
      };
    };
  };

  users = {
    users.${ingestUser} = {
      isSystemUser = true;
      group = ingestUser;
      # Read access to the receive-only gadgetbridge folder (syncthing-owned).
      extraGroups = [ "syncthing" ];
    };
    groups.${ingestUser} = { };
  };

  systemd = {
    tmpfiles.rules = [
      # Group-owned by syncthing so it can traverse into the gadgetbridge
      # import folder below.
      "d ${dataDir} 0750 root syncthing - -"
      "d ${dataDir}/data 0750 root root - -"
      "d ${dataDir}/data/endurain 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainDataDir} 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainLogsDir} 0750 ${toString endurainUid} ${toString endurainGid} - -"
      "d ${endurainPostgresDir} 0700 999 999 - -"
      "d ${gadgetbridgeDir} 0750 syncthing syncthing - -"
    ];

    services = {
      "${containerBackend}-endurain-postgres".preStart = ensureNetworkScript;
      "${containerBackend}-endurain".preStart = ensureNetworkScript;

      endurain-ingest = {
        description = "Upload synced Gadgetbridge activities to Endurain";
        after = [
          "network-online.target"
          endurainUnit
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = ingestUser;
          Group = ingestUser;
          StateDirectory = ingestUser;
          EnvironmentFile = config.sops.secrets."endurain-ingest/env".path;
          Environment = [
            "ENDURAIN_HOST=${endurainHost}"
            "ENDURAIN_WATCH_DIR=${gadgetbridgeGpxDir}"
            "ENDURAIN_STATE_DIR=${ingestStateDir}/markers"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
          ];
          ExecStart = lib.getExe endurainIngest;

          # Hardening: read-only filesystem except the state dir. The watch dir
          # is only ever read (dedup is via markers in the state dir).
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };
    };

    # Primary trigger: react to new files landing in the watch dir. The service
    # only reads the dir (dedup via markers), so it never modifies it and cannot
    # re-trigger itself.
    paths.endurain-ingest = {
      description = "Watch for new Gadgetbridge/OpenTracks activity files";
      wantedBy = [ "paths.target" ];
      pathConfig.PathModified = gadgetbridgeGpxDir;
    };

    # Backstop only: startup catch-up (OnBootSec, for files that arrived while
    # we were down) and a sparse retry for transient upload failures or any
    # missed inotify event. No longer the primary driver.
    timers.endurain-ingest = {
      description = "Backstop for Endurain ingest (startup catch-up + transient retry)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "1h";
        Persistent = true;
      };
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

  services = {
    # Receive Gadgetbridge exports from the phones. rofl-10 only receives; the
    # phones (zf10, px5) are authoritative. The matching devices + Syncthing
    # server are configured in hosts/rofl-10/syncthing.nix.
    syncthing.settings.folders.gadgetbridge = {
      id = gadgetbridgeSyncId;
      label = "Gadgetbridge";
      path = gadgetbridgeDir;
      devices = phoneDevices;
      type = "receiveonly";
    };

    nginx.virtualHosts."${endurainHost}" = {
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

    monit.config = lib.mkAfter ''
      check host "endurain" with address "127.0.0.1"
        group container-services
        restart program = "${pkgs.systemd}/bin/systemctl restart ${endurainUnit}"
        if failed
          port ${toString endurainPort}
          protocol http
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };
}
