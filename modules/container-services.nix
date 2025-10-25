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
    mapAttrs
    concatMap
    attrValues
    concatStringsSep
    attrNames
    optionalString
    optionalAttrs
    filter
    hasPrefix
    ;

  cfg = config.custom.containerServices;

  autheliaDomain = "auth.${config.custom.mainDomain}";

  # Effective Authz URL (can be overridden via options below)
  defaultAuthzURL =
    if cfg.authelia.authzURL != null then
      cfg.authelia.authzURL
    else
      "https://${autheliaDomain}/api/authz/auth-request";

  isHTTPS = hasPrefix "https://" defaultAuthzURL;

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

      credentialsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to an htpasswd-formatted file containing HTTP basic authentication
          credentials (typically provided by a sops secret). When provided the
          service will be protected behind basic auth while still allowing
          requests from 127.0.0.1 without credentials for local monitoring.
        '';
      };

      sso = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Protect this service behind the Authelia SSO gateway. Requests coming
          from localhost or the CGNAT range used by Tailscale/Netbird are
          automatically bypassed according to the Authelia access control
          policy.
        '';
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
      composePath,
      monitoredPort,
      proto,
      extraClause,
    }:
    ''
      check host "${serviceName}" with address "127.0.0.1"
        group services
        restart program = "${pkgs.docker-compose-wrapper}/bin/docker-compose-wrapper -f /srv/${composePath}/docker-compose.yaml up -d --force-recreate --always-recreate-deps ${serviceName}"
          with timeout 180 seconds
        if failed
          port ${monitoredPort}
          protocol ${proto}${optionalString (extraClause != "") " ${extraClause}"}
          with timeout 90 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';

  generateMonitCheck =
    serviceName: service:
    let
      extraClause =
        if service.http_status_code != null then "status " + toString service.http_status_code else "";
      composePath = if service.compose_yaml != null then service.compose_yaml else serviceName;
      monitoredPort = toString service.port;
      proto = if service.tls then "https" else "http";
    in
    monitCheckText {
      inherit
        serviceName
        composePath
        monitoredPort
        proto
        extraClause
        ;
    };

  monitExtraConfig =
    let
      checks = mapAttrs (serviceName: service: generateMonitCheck serviceName service) cfg.services;
    in
    concatStringsSep "\n\n" (attrValues checks);

  createVirtualHost =
    serviceName: service: hostname:
    let
      baseLocation = {
        proxyPass = "http${if service.tls then "s" else ""}://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };

      # Authelia (authz endpoint + modern redirect method)
      autheliaExtraConfig = optionalString service.sso ''
        # Ask Authelia if this request is allowed
        auth_request /internal/authelia/authz;

        # Helpful for debugging 500s: capture subrequest status (e.g., 200/401/403/302)
        auth_request_set $auth_status $upstream_status;

        # Capture Authelia-provided identity and redirect target
        auth_request_set $authelia_user      $upstream_http_remote_user;
        auth_request_set $authelia_groups    $upstream_http_remote_groups;
        auth_request_set $authelia_name      $upstream_http_remote_name;
        auth_request_set $authelia_email     $upstream_http_remote_email;
        auth_request_set $authelia_redirect  $upstream_http_location;

        # Modern redirect: Authelia sets Location; only redirect on 401
        error_page 401 =302 $authelia_redirect;

        # Forward identity headers to the upstream app
        proxy_set_header Remote-User        $authelia_user;
        proxy_set_header Remote-Groups      $authelia_groups;
        proxy_set_header Remote-Name        $authelia_name;
        proxy_set_header Remote-Email       $authelia_email;
        proxy_set_header X-Forwarded-User   $authelia_user;
        proxy_set_header X-Forwarded-Groups $authelia_groups;
        proxy_set_header X-Forwarded-Name   $authelia_name;
        proxy_set_header X-Forwarded-Email  $authelia_email;

        # Forwarding hints some apps expect
        proxy_set_header X-Original-URL   $scheme://$http_host$request_uri;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-URI  $request_uri;
        proxy_set_header X-Forwarded-Ssl  on;

        # Optional: expose auth status for quick curl checks (comment out for prod)
        # add_header X-Auth-Status $auth_status always;
      '';

      # Optional Basic Auth with local/CGNAT bypass at NGINX layer
      basicAuthExtraConfig = optionalString (service.credentialsFile != null) ''
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
          autheliaExtraConfig
          basicAuthExtraConfig
        ]
      );

      locationAttrs =
        baseLocation
        // optionalAttrs (service.credentialsFile != null) {
          basicAuthFile = service.credentialsFile;
        }
        // optionalAttrs (locationExtraConfig != "") {
          extraConfig = locationExtraConfig;
        };

      # Internal location for Authelia authz check
      autheliaAuthzLocation = optionalAttrs service.sso {
        "/internal/authelia/authz" = {
          proxyPass = defaultAuthzURL;
          extraConfig = ''
            internal;

            ${optionalString isHTTPS ''
              # HTTPS to remote Authelia: enable SNI and ensure Host matches the upstream
              proxy_ssl_server_name on;
              proxy_set_header Host $proxy_host;
              proxy_set_header X-Forwarded-Proto $scheme;
            ''}

            # Required headers for Authz call
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Original-URL    $scheme://$http_host$request_uri;
            proxy_set_header X-Forwarded-For   $remote_addr;

            # No body to Authelia
            proxy_set_header Content-Length "";
            proxy_set_header Connection "";
            proxy_pass_request_body off;

            # Reasonable proxy defaults from Authelia examples
            proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
            proxy_redirect http:// $scheme://;
            proxy_http_version 1.1;
            proxy_cache_bypass $cookie_session;
            proxy_no_cache $cookie_session;
            proxy_buffers 4 32k;
            client_body_buffer_size 128k;

            send_timeout 5m;
            proxy_read_timeout 240;
            proxy_send_timeout 240;
            proxy_connect_timeout 240;
          '';
        };
      };
    in
    {
      name = hostname;
      value = {
        default = service.default;
        enableACME = effectiveEnableACME service;
        useACMEHost = effectiveUseACMEHost service;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "/" = locationAttrs;
        }
        // autheliaAuthzLocation;
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
  options.custom.containerServices = {
    enable = mkEnableOption "automatic container virtual host and Monit configuration";

    services = mkOption {
      type = types.attrsOf serviceType;
      default = { };
      description = "Container services exposed through nginx and monitored by Monit.";
    };

    # Where should the auth_request subrequest go?
    # - For local Authelia: "http://127.0.0.1:9091/api/authz/auth-request"
    # - For remote portal:  "https://auth.${config.custom.mainDomain}/api/authz/auth-request"
    authelia.authzURL = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Full URL for the Authelia Authz endpoint used by NGINX auth_request.
        If null, defaults to "https://auth.${config.custom.mainDomain}/api/authz/auth-request".
      '';
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
