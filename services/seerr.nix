{
  config,
  lib,
  ...
}:
let
  dataDir = "/srv/jellyfin";
  seerrConfigDir = "${dataDir}/config/seerr";
  seerrPort = 5055;

  hostnames = [
    "jellyseerr.${config.domains.main}"
    "jellyseerr.arr.${config.domains.main}"
    "seerr.${config.domains.main}"
    "seerr.arr.${config.domains.main}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}        0750 root root - -"
    "d ${seerrConfigDir} 0750 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers.seerr = {
    autoStart = true;
    image = "ghcr.io/seerr-team/seerr:develop@sha256:0b892c15ded64f9941a6c6a0125788f4a56a6b93396e329b1f2902372d980aa0";
    pull = "always";
    extraOptions = [
      "--init"
    ];
    environment = {
      LOG_LEVEL = "debug";
      TZ = config.time.timeZone;
      PORT = toString seerrPort;
    };
    volumes = [
      "${seerrConfigDir}:/app/config"
    ];
    ports = [
      "127.0.0.1:${toString seerrPort}:${toString seerrPort}"
    ];
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    forceSSL = true;
    authelia.enable = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString seerrPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.checks = {
    seerr = {
      type = "host";
      address = "127.0.0.1";
      group = "container-services";
      restartUnit = "${config.virtualisation.oci-containers.backend}-seerr.service";
      conditions = ''
        if failed
          port ${toString seerrPort}
          protocol http
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
