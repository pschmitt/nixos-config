{
  config,
  lib,
  pkgs,
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
    image = "ghcr.io/seerr-team/seerr:develop";
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

  services.monit.config = lib.mkAfter ''
    check host "seerr" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-seerr.service"
      if failed
        port ${toString seerrPort}
        protocol http
        with timeout 15 seconds
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
  '';
}
