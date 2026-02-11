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
    genAttrs
    ;

  cfg = config.custom.containerServices;

  autheliaDomain = "auth.${config.domains.main}";

  trustedStateDir = "/run/container-services";
  nginxTrustedNetworksFile = "${trustedStateDir}/trusted-networks.conf";
  autheliaTrustedNetworksFile = "${trustedStateDir}/authelia-trusted-networks.yml";
  trustedHosts = [ "turris.${config.domains.main}" ];
  autheliaLocalNetworks = [
    "127.0.0.1/32"
    "::1/128"
    "100.64.0.0/10"
  ];
  autheliaInstanceNames = attrNames config.services.authelia.instances;
  autheliaServiceNames = map (name: "authelia-${name}.service") autheliaInstanceNames;
  autheliaUnitsEnv = concatStringsSep " " autheliaServiceNames;
  trustedHostsEnv = concatStringsSep " " trustedHosts;
  autheliaLocalNetworksEnv = concatStringsSep "\n" autheliaLocalNetworks;
  trustedNetworksUpdaterScript = pkgs.writeShellScript "update-container-trusted-networks" (
    builtins.readFile ../services/scripts/update-container-trusted-networks.sh
  );
  nginxServiceName = "nginx.service";

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

  autheliaResolverDirectives =
    let
      formatLine = line: "          " + line;
      joinLines = directives: concatMapStringsSep "\n" formatLine directives + "\n";
      directives =
        if autheliaResolverAddresses == [ ] then
          [ ]
        else
          [
            "resolver ${concatStringsSep " " autheliaResolverAddresses} valid=${cfg.authelia.resolver.validity};"
            "resolver_timeout ${cfg.authelia.resolver.timeout};"
          ];
    in
    if directives == [ ] then "" else joinLines directives;

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

            composeYaml = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional docker-compose project directory.";
            };

            restartAll = mkOption {
              type = types.bool;
              default = true;
              description = "Whether Monit restarts the entire compose stack instead of a single service.";
            };

            restartComposeService = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Compose service name to restart when restartAll = false; defaults to the container service name.";
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
      composePath,
      restartTarget,
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
        restart program = "${pkgs.docker-compose-wrapper}/bin/docker-compose-wrapper -f /srv/${composePath}/docker-compose.yaml up -d --no-deps${
          optionalString (restartTarget != null) " ${restartTarget}"
        }"
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
      inherit (service.monitoring)
        expectedHttpStatusCode
        path
        composeYaml
        restartAll
        restartComposeService
        dependsOn
        group
        ;
      monitorClauses =
        optional (path != null) "request \"${path}\""
        ++ optional (expectedHttpStatusCode != null) "status ${toString expectedHttpStatusCode}";
      extraClause = concatStringsSep " " monitorClauses;
      composePath = if composeYaml != null then composeYaml else serviceName;
      monitoredPort = toString service.port;
      proto = if service.tls then "https" else "http";
      restartTarget =
        if restartAll then
          null
        else
          (if restartComposeService != null then restartComposeService else serviceName);
    in
    monitCheckText {
      inherit
        serviceName
        composePath
        restartTarget
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

  createVirtualHost =
    serviceName: service: hostname:
    let
      baseLocation = {
        proxyPass = "http${if service.tls then "s" else ""}://127.0.0.1:${toString service.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };

      inherit (service) auth;
      wantsBasicAuth = auth.enable && auth.type == "basic";
      wantsSsoAuth = auth.enable && auth.type == "sso";

      # Authelia (authz endpoint using upstream configuration guidance)
      autheliaExtraConfig = optionalString wantsSsoAuth ''
        ## Send a subrequest to Authelia to verify if the user is authenticated and has permission to access the resource.
        auth_request /internal/authelia/authz;

        ## Save the upstream metadata response headers from Authelia to variables.
        auth_request_set $user $upstream_http_remote_user;
        auth_request_set $groups $upstream_http_remote_groups;
        auth_request_set $name $upstream_http_remote_name;
        auth_request_set $email $upstream_http_remote_email;

        ## Configure the redirection when the authz failure occurs. Lines starting with 'Modern Method' and 'Legacy Method'
        ## should be commented / uncommented as pairs. The modern method uses the session cookies configuration's authelia_url
        ## value to determine the redirection URL here. It's much simpler and compatible with the mutli-cookie domain easily.

        ## Modern Method: Set the $redirection_url to the Location header of the response to the Authz endpoint.
        auth_request_set $redirection_url $upstream_http_location;

        ## Inject the metadata response headers from the variables into the request made to the backend.
        proxy_set_header Remote-User $user;
        proxy_set_header Remote-Groups $groups;
        proxy_set_header Remote-Email $email;
        proxy_set_header Remote-Name $name;

        ## Modern Method: When there is a 401 response code from the authz endpoint redirect to the $redirection_url.
        error_page 401 =302 $redirection_url;

        ## Legacy Method: Set $target_url to the original requested URL.
        ## This requires http_set_misc module, replace 'set_escape_uri' with 'set' if you don't have this module.
        # set_escape_uri $target_url $scheme://$http_host$request_uri;

        ## Legacy Method: When there is a 401 response code from the authz endpoint redirect to the portal with the 'rd'
        ## URL parameter set to $target_url. This requires users update 'auth.${config.domains.main}/' with their external
        ## authelia URL.
        # error_page 401 =302 https://auth.${config.domains.main}/?rd=$target_url;
      '';

      # Optional Basic Auth with local/CGNAT bypass at NGINX layer
      basicAuthExtraConfig = optionalString wantsBasicAuth ''
        satisfy any;

        # local (nginx and monitoring)
        allow 127.0.0.1;
        # allow ::1;
        # allow fc00::/7;

        # Netbird + Tailscale IP range (CGNAT)
        allow 100.64.0.0/10;

        # Trusted remote host managed dynamically
        include ${nginxTrustedNetworksFile};

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
        // optionalAttrs wantsBasicAuth {
          basicAuthFile = auth.htpasswdFile;
        }
        // optionalAttrs (locationExtraConfig != "") {
          extraConfig = locationExtraConfig;
        };

      # Internal location for Authelia authz check
      autheliaServerExtraConfig = optionalString wantsSsoAuth ''
        set $upstream_authelia ${defaultAuthzURL};

        ## Virtual endpoint created by nginx to forward auth requests.
        location /internal/authelia/authz {
          ## Essential Proxy Configuration
          internal;
          ${autheliaResolverDirectives}
          proxy_pass $upstream_authelia;

          ## Headers
          ## The headers starting with X-* are required.
          proxy_set_header X-Original-Method $request_method;
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Content-Length "";
          proxy_set_header Connection "";

          ## Basic Proxy Configuration
          proxy_pass_request_body off;
          proxy_next_upstream error timeout invalid_header http_500 http_502 http_503; # Timeout if the real server is dead
          proxy_redirect http:// $scheme://;
          proxy_http_version 1.1;
          proxy_cache_bypass $cookie_session;
          proxy_no_cache $cookie_session;
          proxy_buffers 4 32k;
          client_body_buffer_size 128k;

          ## Advanced Proxy Configuration
          send_timeout 5m;
          proxy_read_timeout 240;
          proxy_send_timeout 240;
          proxy_connect_timeout 240;
        }
      '';
    in
    {
      name = hostname;
      value = {
        inherit (service) default;
        enableACME = effectiveEnableACME service;
        useACMEHost = effectiveUseACMEHost service;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        locations = {
          "/" = locationAttrs;
        };
        extraConfig = autheliaServerExtraConfig;
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
    assertions = authOptionAssertions;
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

    systemd = {
      tmpfiles.rules = [
        "d ${trustedStateDir} 0755 root root -"
      ];

      services = {
        container-services-update-trusted-networks = {
          description = "Update container trusted networks allowlist";
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.coreutils
            pkgs.dnsutils
            pkgs.diffutils
            pkgs.systemd
          ];
          script = ''
            set -eu

            resolver_script=${lib.escapeShellArg trustedNetworksUpdaterScript}
            export NGINX_OUTPUT=${lib.escapeShellArg nginxTrustedNetworksFile}
            export AUTHELIA_OUTPUT=${lib.escapeShellArg autheliaTrustedNetworksFile}
            export NGINX_SERVICE=${lib.escapeShellArg nginxServiceName}
            export AUTHELIA_UNITS=${lib.escapeShellArg autheliaUnitsEnv}
            export TRUSTED_HOSTS=${lib.escapeShellArg trustedHostsEnv}
            export AUTHELIA_LOCAL_NETWORKS=${lib.escapeShellArg autheliaLocalNetworksEnv}

            "$resolver_script"
          '';
        };

        nginx = {
          requires = [ "container-services-update-trusted-networks.service" ];
          after = [ "container-services-update-trusted-networks.service" ];
        };
      }
      // genAttrs (map (name: "authelia-${name}") autheliaInstanceNames) (_: {
        requires = [ "container-services-update-trusted-networks.service" ];
        after = [ "container-services-update-trusted-networks.service" ];
      });

      timers.container-services-update-trusted-networks = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "5m";
        };
      };
    };
  };
}
