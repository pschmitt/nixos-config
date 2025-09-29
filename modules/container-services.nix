{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    mapAttrs
    concatMap
    attrValues
    concatStringsSep
    attrNames
    optionalString
  ;

  cfg = config.custom.containerServices;

  serviceType = types.submodule (_: {
    options = {
      port = mkOption {
        type = types.port;
        description = "Internal port exposed by the container.";
      };

      hosts = mkOption {
        type = types.listOf types.str;
        description = "Hostnames that should route to the container.";
      };

      default = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this virtual host should be the default server.";
      };

      tls = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the container expects TLS at the upstream.";
      };

      http_status_code = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "Optional expected HTTP status code for health checks.";
      };

      compose_yaml = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional docker-compose project directory.";
      };

      enableACME = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Override the ACME enablement for this virtual host.";
      };

      useACMEHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override the ACME certificate to reuse for this host.";
      };
    };
  });

  effectiveEnableACME = service:
    let
      override = service.enableACME;
      base =
        if service.default then cfg.defaultEnableACMEForDefaultHosts else cfg.defaultEnableACME;
    in
    if override != null then override else base;

  effectiveUseACMEHost = service:
    let
      override = service.useACMEHost;
      base =
        if service.default
        then cfg.defaultUseACMEHostForDefaultHosts
        else cfg.defaultUseACMEHost;
    in
    if override != null then override else base;

  generateMonitCheck = serviceName: host: service:
    let
      effectivePort = "443";
      proto = "https";
      extraClause =
        if service.http_status_code != null then "status " + toString service.http_status_code else "";
      composePath =
        if service.compose_yaml != null then service.compose_yaml else serviceName;
    in
    ''
      check host "${serviceName}" with address "${host}"
        group services
        restart program = "${pkgs.docker-compose-wrapper}/bin/docker-compose-wrapper -f /srv/${composePath}/docker-compose.yaml up -d --force-recreate --always-recreate-deps ${serviceName}"
        if failed
          port ${effectivePort}
          protocol ${proto}${optionalString (extraClause != "") " ${extraClause}"}
          with timeout 90 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';

  generatedChecks = mapAttrs (
    serviceName: service:
      let
        firstHost = builtins.head service.hosts;
      in
      generateMonitCheck serviceName firstHost service
  ) cfg.services;

  monitExtraConfig = concatStringsSep "\n\n" (attrValues generatedChecks);

  createVirtualHost = service: hostname: {
    name = hostname;
    value = {
      default = service.default;
      enableACME = effectiveEnableACME service;
      useACMEHost = effectiveUseACMEHost service;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http${if service.tls then "s" else ""}://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };

  virtualHosts = builtins.listToAttrs (
    concatMap (
      serviceName:
        let
          service = cfg.services.${serviceName};
        in
        map (hostname: createVirtualHost service hostname) service.hosts
    ) (attrNames cfg.services)
  );

in
{
  options.custom.containerServices = {
    enable = mkEnableOption "automatic container virtual host and Monit configuration";

    services = mkOption {
      type = types.attrsOf serviceType;
      default = {};
      description = "Container services exposed through nginx and monitored by Monit.";
    };

    defaultEnableACME = mkOption {
      type = types.bool;
      default = true;
      description = "Default ACME enablement for non-default virtual hosts.";
    };

    defaultEnableACMEForDefaultHosts = mkOption {
      type = types.bool;
      default = true;
      description = "Default ACME enablement for virtual hosts marked as default.";
    };

    defaultUseACMEHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default ACME certificate name to reuse for non-default hosts.";
    };

    defaultUseACMEHostForDefaultHosts = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default ACME certificate name to reuse for default hosts.";
    };
  };

  config = mkIf cfg.enable {
    services.nginx.virtualHosts = virtualHosts;
    services.monit.config = lib.mkAfter monitExtraConfig;
  };
}
