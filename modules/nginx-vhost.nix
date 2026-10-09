# Repo-wide extensions of services.nginx.virtualHosts:
#
# - acmeRoot defaults to null: every certificate is issued via DNS-01
#   (security.acme.defaults in services/http.nix), never via the HTTP-01
#   webroot. https://github.com/NixOS/nixpkgs/issues/210807
#
# - authelia.enable puts the vhost behind Authelia SSO (nginx auth_request).
#   It adds the internal authz endpoint to the server block and the
#   auth_request directives to every location; a location opts out with
#   `authelia = false`.
{ config, lib, ... }:
let
  inherit (lib)
    concatStringsSep
    literalExpression
    mkBefore
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  cfg = config.services.nginx.authelia;

  locationSnippet = ''
    ## Send a subrequest to Authelia to verify if the user is authenticated and has permission to access the resource.
    auth_request /internal/authelia/authz;

    ## Save the upstream metadata response headers from Authelia to variables.
    auth_request_set $user $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name $upstream_http_remote_name;
    auth_request_set $email $upstream_http_remote_email;

    ## Modern Method: Set the $redirection_url to the Location header of the response to the Authz endpoint.
    auth_request_set $redirection_url $upstream_http_location;

    ## Inject the metadata response headers from the variables into the request made to the backend.
    proxy_set_header Remote-User $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Email $email;
    proxy_set_header Remote-Name $name;

    ## Modern Method: When there is a 401 response code from the authz endpoint redirect to the $redirection_url.
    error_page 401 =302 $redirection_url;
  '';

  serverSnippet = a: ''
    set $upstream_authelia ${a.authzURL};

    ## Virtual endpoint created by nginx to forward auth requests.
    location /internal/authelia/authz {
      ${optionalString a.apiKeyBypass ''
        ## Bypass Authelia if an API key is present -- the app behind this
        ## vhost is responsible for validating it.
        if ($http_x_api_key) {
          return 200;
        }
      ''}
      ${optionalString a.haIngressBypass ''
        ## Bypass Authelia for HA ingress proxy (Bearer token set by HA)
        if ($authelia_ha_bypass = "1") {
          return 200;
        }
      ''}
      ${optionalString a.forceHeaderBypass ''
        ## Bypass Authelia for callers presenting the host's secret header.
        if ($authelia_force_header_bypass = "1") {
          return 200;
        }
      ''}

      ## Essential Proxy Configuration
      internal;
      ${optionalString (a.resolver.addresses != [ ]) ''
        resolver ${concatStringsSep " " a.resolver.addresses} valid=${a.resolver.validity};
      ''}
      ${optionalString (a.resolver.timeout != null) ''
        resolver_timeout ${a.resolver.timeout};
      ''}
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

  locationModule =
    vhost:
    { config, ... }:
    {
      options.authelia = mkOption {
        type = types.bool;
        default = vhost.authelia.enable;
        defaultText = literalExpression "authelia.enable of the virtual host";
        description = "Whether this location requires Authelia SSO.";
      };

      config.extraConfig = mkIf config.authelia (mkBefore locationSnippet);
    };

  vhostModule =
    { config, ... }:
    {
      options = {
        authelia = {
          enable = mkEnableOption "Authelia SSO (nginx auth_request) for this virtual host";

          authzURL = mkOption {
            type = types.str;
            default = cfg.authzURL;
            defaultText = literalExpression "config.services.nginx.authelia.authzURL";
            description = "Authelia authz endpoint used for the auth_request subrequest.";
          };

          haIngressBypass = mkOption {
            type = types.bool;
            default = cfg.bypassMaps;
            defaultText = literalExpression "config.services.nginx.authelia.bypassMaps";
            description = ''
              Skip Authelia for Home Assistant's ingress proxy ($authelia_ha_bypass).
              Requires the maps from services/authelia-nginx-bypass.nix; nginx
              refuses to start on an unknown variable otherwise.
            '';
          };

          forceHeaderBypass = mkOption {
            type = types.bool;
            default = config.authelia.haIngressBypass;
            defaultText = literalExpression "authelia.haIngressBypass";
            description = ''
              Skip Authelia for callers presenting the host's secret bypass header
              ($authelia_force_header_bypass, same map module as haIngressBypass).
            '';
          };

          apiKeyBypass = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Skip Authelia whenever the request carries an X-API-Key header. The
              header is never checked here -- any value passes -- so this is only
              sound in front of an app that authenticates the key itself.
            '';
          };

          resolver = {
            addresses = mkOption {
              type = types.listOf types.str;
              default = [ "1.1.1.1" ];
              description = "DNS resolvers nginx uses to look up the authz endpoint.";
            };

            validity = mkOption {
              type = types.str;
              default = "30s";
              description = "Resolver cache validity for the authz endpoint.";
            };

            timeout = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "resolver_timeout for authz lookups (nginx default when null).";
            };
          };
        };

        locations = mkOption {
          type = types.attrsOf (types.submodule (locationModule config));
        };
      };

      config = {
        acmeRoot = mkDefault null;
        extraConfig = mkIf config.authelia.enable (mkBefore (serverSnippet config.authelia));
      };
    };
in
{
  options.services.nginx = {
    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule vhostModule);
    };

    authelia = {
      authzURL = mkOption {
        type = types.str;
        default = "https://auth.${config.domains.main}/api/authz/auth-request";
        defaultText = literalExpression ''"https://auth.''${config.domains.main}/api/authz/auth-request"'';
        description = "Default Authelia authz endpoint for virtual hosts with authelia.enable.";
      };

      bypassMaps = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether the $authelia_ha_bypass and $authelia_force_header_bypass maps
          are defined on this host (set by services/authelia-nginx-bypass.nix).
          Default for every vhost's authelia.haIngressBypass.
        '';
      };
    };
  };
}
