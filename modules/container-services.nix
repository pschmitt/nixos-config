{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    concatMapStringsSep
    mapAttrs
    concatMap
    attrValues
    concatStringsSep
    attrNames
    optional
    optionalString
    optionalAttrs
    filter
    ;

  cfg = config.services.containerServices;

  autheliaDomain = "auth.${config.domains.main}";

  # Effective Authz URL (can be overridden via options below)
  defaultAuthzURL =
    if cfg.authelia.authzURL != null then
      cfg.authelia.authzURL
    else
      "https://${autheliaDomain}/api/authz/auth-request";

  autheliaResolverAddresses =
    let
      configured = cfg.authelia.resolver.addresses;
      fallback =
        let
          inherit (config.networking) nameservers;
        in
        if nameservers != [ ] then nameservers else [ "127.0.0.53" ];
    in
    if configured != null then configured else fallback;

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

      monitoring = mkOption {
        description = "Monitoring configuration applied to Monit checks for this service.";
        default = { };
        type = types.submodule (_: {
          options = {
            expectedHttpStatusCode = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Optional expected HTTP status code for health checks.";
            };

            path = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional HTTP request path for health checks.";
            };

            restart = {
              systemdUnit = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Systemd unit Monit restarts when this service is unhealthy.";
              };

            };

            restartAfterFailures = mkOption {
              type = types.ints.positive;
              default = 1;
              description = "Consecutive failed program checks before Monit restarts this service.";
            };

            dependsOn = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional dependency for the Monit check.";
            };

            group = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Monit group name";
            };

            program = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional program path for a custom Monit check.";
            };
          };
        });
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

      extraLocationConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra raw NGINX directives appended to the service's proxy
          location block (e.g. to override proxy timeouts for
          long-running transfers).
        '';
      };

      auth = mkOption {
        description = "Authentication policy for the container service.";
        default = { };
        type = types.submodule (_: {
          options = {
            enable = mkEnableOption "authentication for this service";

            type = mkOption {
              type = types.enum [
                "basic"
                "sso"
              ];
              default = "sso";
              defaultText = "\"sso\"";
              description = ''
                Authentication mode to enforce when auth is enabled.
                Supported values are:
                  - "basic": HTTP basic authentication backed by an htpasswd
                    file.
                  - "sso": Authelia single sign-on protection.
              '';
            };

            htpasswdFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = ''
                Path to an htpasswd-formatted file containing HTTP basic
                authentication credentials (typically provided by a sops
                secret). Required when ``type = "basic"``.
              '';
            };
          };
        });
      };
    };
  });

  effectiveEnableACME =
    service:
    let
      override = service.enableACME;
      base = if service.default then cfg.defaultEnableACMEForDefaultHosts else cfg.defaultEnableACME;
    in
    if override != null then override else base;

  effectiveUseACMEHost =
    service:
    let
      override = service.useACMEHost;
      base = if service.default then cfg.defaultUseACMEHostForDefaultHosts else cfg.defaultUseACMEHost;
    in
    if override != null then override else base;

  monitCheckText =
    {
      serviceName,
      restartCommand,
      monitoredPort,
      proto,
      extraClause,
      dependsOn,
      group,
    }:
    ''
      check host "${serviceName}" with address "127.0.0.1"
        group container-services
        ${optionalString (group != null) "group ${group}"}
        ${optionalString (dependsOn != null) "depends on ${dependsOn}"}
        restart program = "${restartCommand}"
          with timeout 180 seconds
        if failed
          port ${monitoredPort}
          protocol ${proto}${optionalString (extraClause != "") " ${extraClause}"}
          with timeout 90 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';

  monitProgramCheckText =
    {
      serviceName,
      restartCommand,
      program,
      dependsOn,
      group,
      restartAfterFailures,
    }:
    let
      restartCondition =
        if restartAfterFailures == 1 then
          "if status != 0 then restart"
        else
          "if status != 0 for ${toString restartAfterFailures} cycles then restart";
    in
    ''
      check program "${serviceName}" with path "${program}"
        group container-services
        ${optionalString (group != null) "group ${group}"}
        ${optionalString (dependsOn != null) "depends on ${dependsOn}"}
        restart program = "${restartCommand}"
          with timeout 180 seconds
      ${restartCondition}
        if 5 restarts within 10 cycles then alert
    '';

  restartProgram =
    service: "${pkgs.systemd}/bin/systemctl restart ${service.monitoring.restart.systemdUnit}";

  generateMonitCheck =
    serviceName: service:
    let
      inherit (service.monitoring)
        expectedHttpStatusCode
        path
        dependsOn
        group
        program
        ;
      inherit (service.monitoring) restartAfterFailures;
      monitorClauses =
        optional (path != null) "request \"${path}\""
        ++ optional (expectedHttpStatusCode != null) "status ${toString expectedHttpStatusCode}";
      extraClause = concatStringsSep " " monitorClauses;
      monitoredPort = toString service.port;
      proto = if service.tls then "https" else "http";
      restartCommand = restartProgram service;
    in
    if program != null then
      monitProgramCheckText {
        inherit
          serviceName
          restartCommand
          program
          dependsOn
          group
          restartAfterFailures
          ;
      }
    else
      monitCheckText {
        inherit
          serviceName
          restartCommand
          monitoredPort
          proto
          extraClause
          dependsOn
          group
          ;
      };

  monitExtraConfig =
    let
      checks = mapAttrs (serviceName: service: generateMonitCheck serviceName service) cfg.services;
    in
    concatStringsSep "\n\n" (attrValues checks);

  authOptionAssertions = concatMap (
    serviceName:
    let
      service = cfg.services.${serviceName};
      inherit (service) auth;
      inherit (auth) enable htpasswdFile;
      authType = auth.type;
      wantsBasic = enable && authType == "basic";
    in
    optional wantsBasic {
      assertion = htpasswdFile != null;
      message = "Container service '${serviceName}' requires auth.htpasswdFile when using basic auth.";
    }
    ++ optional (htpasswdFile != null && !wantsBasic) {
      assertion = false;
      message = "Container service '${serviceName}' should only set auth.htpasswdFile when auth.type = \"basic\".";
    }
  ) (attrNames cfg.services);

  restartOptionAssertions = concatMap (
    serviceName:
    let
      restart = cfg.services.${serviceName}.monitoring.restart;
    in
    optional (restart.systemdUnit == null) {
      assertion = false;
      message = "Container service '${serviceName}' must set monitoring.restart.systemdUnit.";
    }
  ) (attrNames cfg.services);

  createVirtualHost =
    _serviceName: service: hostname:
    let
      baseLocation = {
        proxyPass = "http${if service.tls then "s" else ""}://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };

      inherit (service) auth;
      wantsBasicAuth = auth.enable && auth.type == "basic";
      wantsSsoAuth = auth.enable && auth.type == "sso";

      # Optional Basic Auth with local/CGNAT bypass at NGINX layer
      basicAuthExtraConfig = optionalString wantsBasicAuth ''
        satisfy any;

        # local (nginx and monitoring)
        allow 127.0.0.1;
        # allow ::1;
        # allow fc00::/7;

        # Netbird + Tailscale IP range (CGNAT)
        allow 100.64.0.0/10;

        # Reject all other requests unless basic auth succeeds
        deny all;
      '';

      locationExtraConfig = concatStringsSep "\n\n" (
        filter (cfg: cfg != "") [
          basicAuthExtraConfig
          service.extraLocationConfig
        ]
      );

      locationAttrs =
        baseLocation
        // optionalAttrs wantsBasicAuth {
          basicAuthFile = auth.htpasswdFile;
        }
        // optionalAttrs (locationExtraConfig != "") {
          extraConfig = locationExtraConfig;
        };

    in
    {
      name = hostname;
      value = {
        inherit (service) default;
        enableACME = effectiveEnableACME service;
        useACMEHost = effectiveUseACMEHost service;
        forceSSL = true;
        locations = {
          "/" = locationAttrs;
        };
        authelia = {
          enable = wantsSsoAuth;
          haIngressBypass = false;
          authzURL = defaultAuthzURL;
          resolver = {
            addresses = autheliaResolverAddresses;
            inherit (cfg.authelia.resolver) validity timeout;
          };
        };
      };
    };

  virtualHosts = builtins.listToAttrs (
    concatMap (
      serviceName:
      let
        service = cfg.services.${serviceName};
      in
      map (hostname: createVirtualHost serviceName service hostname) service.hosts
    ) (attrNames cfg.services)
  );

in
{
  options.services.containerServices = {
    enable = mkEnableOption "automatic container virtual host and Monit configuration";

    services = mkOption {
      type = types.attrsOf serviceType;
      default = { };
      description = "Container services exposed through nginx and monitored by Monit.";
    };

    # Where should the auth_request subrequest go?
    # - For local Authelia: "http://127.0.0.1:9091/api/authz/auth-request"
    # - For remote portal:  "https://auth.${config.domains.main}/api/authz/auth-request"
    authelia.authzURL = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Full URL for the Authelia Authz endpoint used by NGINX auth_request.
        If null, defaults to "https://auth.${config.domains.main}/api/authz/auth-request".
      '';
    };

    authelia.resolver = {
      addresses = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = ''
          List of DNS resolver addresses exposed to NGINX when proxying Authelia
          authorization subrequests. When null, falls back to the system
          nameservers (or 127.0.0.53 if none are defined).
        '';
      };

      validity = mkOption {
        type = types.str;
        default = "30s";
        description = ''
          Resolver cache validity for the Authelia authorization upstream.
        '';
      };

      timeout = mkOption {
        type = types.str;
        default = "5s";
        description = ''
          Timeout applied to Authelia authorization DNS lookups.
        '';
      };
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

    enableRedirection = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable NFTables redirection for container services.";
    };

    trustedInterfacePatterns = mkOption {
      type = types.listOf types.str;
      default = [
        "nb-*"
        "tailscale*"
      ];
      description = "Interface patterns to enable redirection and route_localnet for.";
    };
  };

  config = mkIf cfg.enable {
    assertions = authOptionAssertions ++ restartOptionAssertions;
    services.nginx.virtualHosts = virtualHosts;
    services.monit.config = lib.mkAfter monitExtraConfig;

    networking.nftables = mkIf cfg.enableRedirection {
      enable = true;
      tables."nat-redirection" = {
        family = "ip";
        content = ''
          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;
            ${concatMapStringsSep "\n            " (
              service:
              "iifname { ${
                concatMapStringsSep ", " (p: "\"${p}\"") cfg.trustedInterfacePatterns
              } } tcp dport ${toString service.port} dnat to 127.0.0.1:${toString service.port}"
            ) (attrValues cfg.services)}
          }
        '';
      };
    };
  };
}
