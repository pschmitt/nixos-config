{
  config,
  lib,
  pkgs,
  ...
}:

let
  services = {
    jellyfin = {
      port = 8096;
      hosts = [
        "tv.${config.custom.mainDomain}"
        "jelly.${config.networking.hostName}.${config.custom.mainDomain}"
        "jelly.${config.custom.mainDomain}"
        "jellyfin.${config.networking.hostName}.${config.custom.mainDomain}"
        "jellyfin.${config.custom.mainDomain}"
        "media.${config.custom.mainDomain}"
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
      compose_yaml = "piracy";
    };
    sonarr = {
      port = 8989;
      hosts = [
        "snr.${config.custom.mainDomain}"
        "sonarr.${config.custom.mainDomain}"
        "snr.${config.networking.hostName}.${config.custom.mainDomain}"
        "sonarr.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
      compose_yaml = "piracy";
    };
    tdarr = {
      port = 8265;
      hosts = [
        "tdarr.${config.custom.mainDomain}"
        "tdarr.${config.networking.hostName}.${config.custom.mainDomain}"
      ];
    };
    transmission = {
      port = 9091;
      hosts = [
        "to.${config.custom.mainDomain}"
        "to.${config.networking.hostName}.${config.custom.mainDomain}"
      ];

      http_status_code = 401;
      compose_yaml = "piracy";
    };
  };

  # Helper function to generate a Monit config snippet.
  generateMonitCheck =
    serviceName: host: service:
    let
      effectivePort = "443";
      proto = "https";
      extraClause =
        if service ? http_status_code then "status " + toString service.http_status_code else "";
      composePath = if service ? compose_yaml then service.compose_yaml else serviceName;
    in
    ''
      check host "${serviceName}" with address "${host}"
        group services
        restart program = "${pkgs.docker-compose-wrapper}/bin/docker-compose-wrapper -f /srv/${composePath}/docker-compose.yaml up -d --force-recreate ${serviceName}"
        if failed
          port ${effectivePort}
          protocol ${proto} ${extraClause}
          with timeout 15 seconds
          and certificate valid for 5 days
        then restart
        if 5 restarts within 10 cycles then alert
    '';

  # Generate a config snippet for each service using its service name and main host.
  generatedChecks = lib.mapAttrs (
    serviceName: service:
    let
      firstHost = builtins.head service.hosts;
    in
    generateMonitCheck serviceName firstHost service
  ) services;

  monitExtraConfig = lib.concatStringsSep "\n\n" (lib.attrValues generatedChecks);

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
  imports = [ ../../services/docker-compose-bulk.nix ];

  services.nginx.virtualHosts = virtualHosts;
  services.monit.config = lib.mkAfter monitExtraConfig;
}
