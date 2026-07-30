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
  jellyfinUid = 1000;
  jellyfinGid = 1000;

  hostnames = [
    "tv.${config.domains.main}"
    "media.${config.domains.main}"
    "jellyfin.${config.domains.main}"
    "jelly.${config.domains.main}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}             0750 root root - -"
    "d ${jellyfinConfigDir}   0750 ${toString jellyfinUid} ${toString jellyfinGid} - -"

    # Sonarr/Radarr own the shows/movies they import (sonarr:sonarr,
    # radarr:radarr) and only grant themselves a default ACL entry on the
    # library roots, so jellyfin's PUID falls through to `other` (r-x) on
    # anything they create - fine for playback, but "Delete from Jellyfin"
    # needs write on the containing directory and fails with a 500
    # (UnauthorizedAccessException) instead. Add jellyfin's PUID as its own
    # default ACL entry so it inherits down to every show/season/movie dir
    # created from here on, the same way the sonarr/radarr entries already do.
    "a+ ${config.arr.dirs.tvShows} - - - - u:${toString jellyfinUid}:rwx"
    "A+ ${config.arr.dirs.tvShows} - - - - u:${toString jellyfinUid}:rwx"
    "a+ ${config.arr.dirs.movies}  - - - - u:${toString jellyfinUid}:rwx"
    "A+ ${config.arr.dirs.movies}  - - - - u:${toString jellyfinUid}:rwx"
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    autoStart = true;
    image = "lscr.io/linuxserver/jellyfin:latest";
    pull = "always";
    extraOptions = [
      "--hostname=${config.networking.hostName}"
    ];
    environment = {
      PUID = toString jellyfinUid;
      PGID = toString jellyfinGid;
      TZ = config.time.timeZone;
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
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
  '';
}
