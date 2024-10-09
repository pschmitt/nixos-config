{ config, lib, ... }:

let
  services = {
    archivebox = {
      port = 27244;
      hosts = [
        "arc.brkn.lol"
        "archive.brkn.lol"
        "archivebox.brkn.lol"
        "arc.${config.networking.hostName}.brkn.lol"
        "archive.${config.networking.hostName}.brkn.lol"
        "archivebox.${config.networking.hostName}.brkn.lol"
      ];
    };
    jellyfin = {
      port = 8096;
      hosts = [
        "jelly.${config.networking.hostName}.brkn.lol"
        "jelly.brkn.lol"
        "jellyfin.${config.networking.hostName}.brkn.lol"
        "jellyfin.brkn.lol"
        "media.heimat.dev"
        "tv.brkn.lol"

        # TODO Remove
        "jelly.${config.networking.hostName}.heimat.dev"
        "jelly.heimat.dev"
        "jellyfin.${config.networking.hostName}.heimat.dev"
        "jellyfin.heimat.dev"
        "media.heimat.dev"
        "tv.heimat.dev"
      ];
    };
    podsync = {
      port = 7637;
      hosts = [
        "podcasts.brkn.lol"
        "podsync.brkn.lol"
        "podsync.${config.networking.hostName}.brkn.lol"
        "podsync.${config.networking.hostName}.heimat.dev"
      ];
    };
    radarr = {
      port = 7878;
      hosts = [
        "rdr.brkn.lol"
        "radarr.brkn.lol"
        "rdr.${config.networking.hostName}.brkn.lol"
        "radarr.${config.networking.hostName}.brkn.lol"
      ];
    };
    sonarr = {
      port = 8989;
      hosts = [
        "snr.brkn.lol"
        "sonarr.brkn.lol"
        "snr.${config.networking.hostName}.brkn.lol"
        "sonarr.${config.networking.hostName}.brkn.lol"
      ];
    };
    tdarr = {
      port = 8265;
      hosts = [
        "tdarr.brkn.lol"
        "tdarr.${config.networking.hostName}.brkn.lol"
      ];
    };
    transmission = {
      port = 9091;
      hosts = [
        "to.brkn.lol"
        "torrent.brkn.lol"
        "to.${config.networking.hostName}.brkn.lol"
        "torrent.${config.networking.hostName}.brkn.lol"
      ];
    };
  };

  # Helper function to create virtual hosts for each service
  createVirtualHost = service: hostname: {
    name = hostname;
    value = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  # Generate virtual hosts for all services and their hostnames
  virtualHosts = builtins.listToAttrs (
    lib.concatMap (
      serviceName:
      let
        service = services.${serviceName};
      in
      map (hostname: createVirtualHost service hostname) service.hosts
    ) (builtins.attrNames services)
  );
in
{
  services.nginx.virtualHosts = virtualHosts;
}
