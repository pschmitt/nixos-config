{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/jellyfin";
  jellyfinConfigDir = "${dataDir}/config/jellyfin";
  jellyfinPort = 8096;

  hostnames = [
    "tv.${config.domains.main}"
    "media.${config.domains.main}"
    "jellyfin.${config.domains.main}"
    "jelly.${config.domains.main}"
    "jelly.${config.networking.hostName}.${config.domains.main}"
    "jellyfin.${config.networking.hostName}.${config.domains.main}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}             0750 root root - -"
    "d ${jellyfinConfigDir}   0750 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    autoStart = true;
    image = "lscr.io/linuxserver/jellyfin:latest";
    pull = "always";
    extraOptions = [
      "--hostname=${config.networking.hostName}"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Berlin";
    };
    volumes = [
      "${jellyfinConfigDir}:/config"
      "/mnt/data/videos:/videos"
    ];
    ports = [
      "127.0.0.1:${toString jellyfinPort}:${toString jellyfinPort}"
    ];
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString jellyfinPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "jellyfin" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-jellyfin.service"
      if failed
        port ${toString jellyfinPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
