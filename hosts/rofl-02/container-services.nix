{ config, lib, ... }:

let
  services = {
    alby-hub = {
      port = 25294;
      hosts = [
        "alby.${config.custom.mainDomain}"
      ];
    };
    archivebox = {
      port = 27244;
      hosts = [
        "arc.${config.custom.mainDomain}"
        "archive.${config.custom.mainDomain}"
        "archivebox.${config.custom.mainDomain}"
        "arc.${config.networking.hostName}.${config.custom.mainDomain}"
        "archive.${config.networking.hostName}.${config.custom.mainDomain}"
        "archivebox.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    hoarder = {
      port = 46273;
      hosts = [
        "hoarder.${config.custom.mainDomain}"
      ];
    };
    jellyfin = {
      port = 8096;
      hosts = [
        "jelly.${config.networking.hostName}.${config.custom.mainDomain}"
        "jelly.${config.custom.mainDomain}"
        "jellyfin.${config.networking.hostName}.${config.custom.mainDomain}"
        "jellyfin.${config.custom.mainDomain}"
        "media.${config.custom.mainDomain}"
        "tv.${config.custom.mainDomain}"
      ];
    };
    memos = {
      port = 63667;
      hosts = [
        "memos.${config.custom.mainDomain}"
      ];
    };
    n8n = {
      port = 5678;
      hosts = [
        "n8n.${config.custom.mainDomain}"
      ];
    };
    nextcloud = {
      port = 63982;
      tls = true;
      hosts = [
        "c.${config.custom.mainDomain}"
        "nextcloud.${config.custom.mainDomain}"
        "c.${config.networking.hostName}.${config.custom.mainDomain}"
        "nextcloud.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    open-webui = {
      port = 6736;
      hosts = [
        "ai.${config.custom.mainDomain}"
      ];
    };
    pp = {
      port = 9999;
      hosts = [
        "pp.${config.custom.mainDomain}"
      ];
    };
    podsync = {
      port = 7637;
      hosts = [
        "podcasts.${config.custom.mainDomain}"
        "podsync.${config.custom.mainDomain}"
        "podsync.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    radarr = {
      port = 7878;
      hosts = [
        "rdr.${config.custom.mainDomain}"
        "radarr.${config.custom.mainDomain}"
        "rdr.${config.networking.hostName}.${config.custom.mainDomain}"
        "radarr.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    stirling-pdf = {
      port = 18733;
      hosts = [ "pdf.${config.custom.mainDomain}" ];
    };
    sonarr = {
      port = 8989;
      hosts = [
        "snr.${config.custom.mainDomain}"
        "sonarr.${config.custom.mainDomain}"
        "snr.${config.networking.hostName}.${config.custom.mainDomain}"
        "sonarr.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    tdarr = {
      port = 8265;
      hosts = [
        "tdarr.${config.custom.mainDomain}"
        "tdarr.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    # traefik = {
    #   port = 8723; # http: 18723
    #   default = true;
    # FIXME Below is not valid config!
    # You probably want to use:
    # services.nginx.virtualHosts.<name>.useACMEHost
    #   hosts = ["*.${config.custom.mainDomain}"];
    # };
    transmission = {
      port = 9091;
      hosts = [
        "to.${config.custom.mainDomain}"
        "torrent.${config.custom.mainDomain}"
        "to.${config.networking.hostName}.${config.custom.mainDomain}"
        "torrent.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    wallos = {
      port = 8282;
      hosts = [ "subs.${config.custom.mainDomain}" ];
    };
    whoami = {
      port = 19462;
      hosts = [
        # FIXME Below is not valid config!
        # You probably want to use:
        # services.nginx.virtualHosts.<name>.useACMEHost
        # "*.${config.custom.mainDomain}"
        "whoami.${config.custom.mainDomain}"
      ];
      default = true;
    };
    wikijs = {
      port = 9454;
      hosts = [ "wiki.${config.custom.mainDomain}" ];
    };
  };

  # Helper function to create virtual hosts for each service
  createVirtualHost = service: hostname: {
    name = hostname;
    value = {
      default = service.default or false;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http${if service.tls or false then "s" else ""}://127.0.0.1:${toString service.port}";
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
