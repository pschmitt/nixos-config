{
  config,
  lib,
  pkgs,
  ...
}:

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
    dawarich = {
      port = 32927;
      hosts = [
        "dawarich.${config.custom.mainDomain}"
        "location.${config.custom.mainDomain}"
      ];
    };
    # hoarder = {
    #   port = 46273;
    #   hosts = [
    #     "hoarder.${config.custom.mainDomain}"
    #   ];
    # };
    mealie = {
      port = 63254;
      hosts = [
        "nom.${config.custom.mainDomain}"
      ];
    };
    # memos = {
    #   port = 63667;
    #   hosts = [
    #     "memos.${config.custom.mainDomain}"
    #   ];
    # };
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
    stirling-pdf = {
      port = 18733;
      hosts = [ "pdf.${config.custom.mainDomain}" ];
    };
    # traefik = {
    #   port = 8723; # http: 18723
    #   default = true;
    # };
    wallos = {
      port = 8282;
      hosts = [ "subs.${config.custom.mainDomain}" ];
    };
    whoami = {
      port = 19462;
      hosts = [
        "whoami.${config.custom.mainDomain}"
      ];
      default = true;
    };
    wikijs = {
      port = 9454;
      hosts = [ "wiki.${config.custom.mainDomain}" ];
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
      enableACME = (if service.default or false then false else true);
      useACMEHost = (if service.default or false then "wildcard.${config.custom.mainDomain}" else null);
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

  # wildcard cert
  security.acme.certs."wildcard.${config.custom.mainDomain}" = {
    domain = "*.${config.custom.mainDomain}";
    group = "nginx";
  };

  services.nginx.virtualHosts = virtualHosts;
  services.monit.config = lib.mkAfter monitExtraConfig;
}
