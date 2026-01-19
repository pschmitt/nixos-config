{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:

let
  autheliaDomain = "auth.${config.domains.main}";
  autheliaAuthzURL = "https://${autheliaDomain}/api/authz/auth-request";
  autheliaResolverAddresses =
    let
      inherit (config.networking) nameservers;
      stub = "127.0.0.53";
    in
    if nameservers != [ ] then nameservers else [ stub ];
  autheliaResolverDirectives = ''
    resolver ${lib.concatStringsSep " " autheliaResolverAddresses} valid=30s;
    resolver_timeout 5s;
  '';
in
{
  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules =
    let
      user = config.users.users.github-actions.name;
      inherit (config.services.nginx) group;
    in
    [
      # Fix ISO/IMG upload directory ownership (readable by nginx)
      "Z /mnt/data/blobs/iso 0750 ${user} ${group} - -"
      "Z /mnt/data/blobs/img 0750 ${user} ${group} - -"
    ];

  services.nginx.virtualHosts = {
    "blobs.${config.domains.main}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = false; # disabled on purpose!
      addSSL = true; # required to actually response on https requests
      root = "/mnt/data/blobs";
      locations = {
        "/" = {
          extraConfig = ''
            autoindex on;
            autoindex_localtime on;
          '';
        };

        "/private/" = {
          # Lock down the private subtree via Authelia while still offering listings.
          extraConfig = ''
            autoindex on;
            autoindex_localtime on;

            set $authelia_basic_request 0;
            if ($http_authorization != "") {
              set $authelia_basic_request 1;
            }

            auth_request /internal/authelia/authz;
            auth_request_set $user $upstream_http_remote_user;
            auth_request_set $groups $upstream_http_remote_groups;
            auth_request_set $name $upstream_http_remote_name;
            auth_request_set $email $upstream_http_remote_email;
            auth_request_set $redirection_url $upstream_http_location;

            proxy_set_header Remote-User $user;
            proxy_set_header Remote-Groups $groups;
            proxy_set_header Remote-Name $name;
            proxy_set_header Remote-Email $email;

            error_page 401 = @authelia401;
          '';
        };

        "/internal/authelia/authz" = {
          extraConfig = ''
            internal;
            ${autheliaResolverDirectives}

            set $authelia_upstream ${autheliaAuthzURL};
            if ($http_authorization != "") {
              set $authelia_upstream ${autheliaAuthzURL}?auth=basic;
            }

            proxy_pass $authelia_upstream;
            proxy_ssl_server_name on;
            proxy_ssl_name ${autheliaDomain};
            proxy_set_header Host ${autheliaDomain};
            proxy_set_header Authorization $http_authorization;
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header Content-Length "";
            proxy_set_header Connection "";
            proxy_pass_request_body off;
            proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
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

        "@authelia401" = {
          extraConfig = ''
            if ($authelia_basic_request = 1) {
              return 401;
            }

            return 302 $redirection_url;
          '';
        };

      };
    };

    "p.${config.domains.main}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        root = inputs.pschmitt-dev.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    };

    "y.${config.domains.main}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        return = "301 https://raw.githubusercontent.com/pschmitt/yadm-init/main/init.sh";
      };
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "http-static-blobs" with address "blobs.${config.domains.main}"
      group nginx
      group services
      if failed
        port 443
        protocol https
        with timeout 15 seconds
      then alert
  '';
}
