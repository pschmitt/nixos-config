{ config, lib, ... }:

let
  services = {
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
