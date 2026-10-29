{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostnames = [
    "paperless.${config.domains.main}"
    "paperless.${config.networking.hostName}.${config.domains.main}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;
  hostnamesWithSchema = map (host: "https://${host}") hostnames;

  forwarder = pkgs.writers.writePython3Bin "paperless-forwarder" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/paperless-forwarder.py);
  # Inside the consume dir (ignored by the consumer) so the final rename
  # stays on one mount: ReadWritePaths bind-mounts each path separately.
  forwarderStagingName = ".forwarder-staging";
  forwarderStaging = "${config.services.paperless.consumptionDir}/${forwarderStagingName}";
  forwarderStateDir = "/var/lib/paperless-forwarder";
  forwarderArgs = [
    (lib.getExe forwarder)
    "--source"
    "/mnt/data/srv/syncthing/documents"
    "--consume"
    config.services.paperless.consumptionDir
    "--staging"
    forwarderStaging
    "--state"
    "${forwarderStateDir}/state.json"
    "--exclude"
    "notes"
  ];
in
{
  sops.secrets."paperless-ngx/adminPassword" = config.sops.mkHostSecret {
  };

  systemd = {
    # Forward new files from the Syncthing documents tree into the consume
    # dir. Unlike a mirror (lsyncd), it remembers what it already forwarded,
    # so restarts never re-feed the library after Paperless consumed it.
    # A fresh host needs a one-time baseline: `paperless-forwarder --init`.
    services.paperless-forwarder = {
      description = "Forward new documents to the Paperless consume dir";
      after = [ "paperless-consumer.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.escapeShellArgs forwarderArgs;
        User = config.services.paperless.user;
        Group = config.services.paperless.user;
        # Read-only access to library files that are not world-readable.
        AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
        CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
        Nice = 10;
        IOSchedulingClass = "idle";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [
          config.services.paperless.consumptionDir
          forwarderStateDir
        ];
      };
    };

    timers.paperless-forwarder = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitInactiveSec = "5min";
      };
    };

    tmpfiles.settings."10-paperless" =
      let
        inherit (config.services.paperless) user;

        defaultRule = {
          inherit user;
          group = user;
          mode = "755"; # enforce mode for all dirs
        };
      in
      {
        "${config.services.paperless.dataDir}".d = defaultRule;
        "${config.services.paperless.mediaDir}".d = defaultRule;
        "${config.services.paperless.consumptionDir}".d = defaultRule;
        "${forwarderStaging}".d = defaultRule;
        "${forwarderStateDir}".d = defaultRule;
      };
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "paperless-forwarder" ''
      exec ${lib.getExe' pkgs.util-linux "setpriv"} --reuid=${config.services.paperless.user} \
        --regid=${config.services.paperless.user} --init-groups \
        --inh-caps=+dac_read_search --ambient-caps=+dac_read_search -- \
        ${lib.escapeShellArgs forwarderArgs} "$@"
    '')
  ];

  services = {
    paperless = {
      enable = true;
      # Flaky test reads local time from a file's mtime; excluded upstream
      # before nixpkgs commit d6524aa dropped that exclusion.
      package = pkgs.paperless-ngx.overrideAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [
          "testNormalOperation"
        ];
      });

      domain = primaryHost;
      address = "127.0.0.1";
      port = 28981;

      dataDir = "/mnt/data/srv/paperless-ngx/data";
      mediaDir = "/mnt/data/srv/paperless-ngx/data/media";
      consumptionDir = "/mnt/data/srv/paperless-ngx/data/consume";
      consumptionDirIsPublic = false;

      # https://docs.paperless-ngx.com/configuration/
      settings = {
        PAPERLESS_ADMIN_USER = config.mainUser.username;

        PAPERLESS_ALLOWED_HOSTS = lib.concatStringsSep "," hostnames;
        PAPERLESS_CORS_ALLOWED_HOSTS = lib.concatStringsSep "," hostnamesWithSchema;
        PAPERLESS_CSRF_TRUSTED_ORIGINS = lib.concatStringsSep "," hostnamesWithSchema;

        PAPERLESS_OCR_LANGUAGE = "deu+fra+eng";
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
        PAPERLESS_CONSUMER_IGNORE_DIRS = builtins.toJSON [ forwarderStagingName ];
        PAPERLESS_CONSUMER_DELETE_DUPLICATES = true;

        PAPERLESS_FILENAME_FORMAT = "{original_name}";
      };
      passwordFile = config.sops.secrets."paperless-ngx/adminPassword".path;
    };

    # networking.firewall.allowedTCPPorts = [ config.services.paperless.port ];

    nginx.virtualHosts."${primaryHost}" = {
      inherit serverAliases;
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://${config.services.paperless.address}:${toString config.services.paperless.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.checks = {
      paperless-ngx = {
        type = "host";
        address = "${config.services.paperless.address}";
        group = "services";
        restartProgram = "${pkgs.systemd}/bin/systemctl restart paperless-consumer.service paperless-scheduler.service paperless-task-queue.service paperless-web.service redis-paperless.service";
        conditions = ''
          if failed
            port ${toString config.services.paperless.port}
            protocol http
            request "/"
            with hostheader "${primaryHost}"
            with timeout 15 seconds
            for 3 cycles
          then restart
          if 3 restarts within 15 cycles then alert
        '';
      };
    };
  };

  users.users."${config.mainUser.username}" = {
    extraGroups = [ "paperless" ];
  };
}
