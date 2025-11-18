{ config, pkgs, ... }:

let
  autheliaDomain = "auth.${config.custom.mainDomain}";
  autheliaAuthzURL = "http://127.0.0.1:28843/api/authz/auth-request";
in
{
  services.nginx.virtualHosts = {
    "blobs.${config.custom.mainDomain}" = {
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

            error_page 401 =302 $redirection_url;
          '';
        };
        "/internal/authelia/authz" = {
          extraConfig = ''
            internal;
            proxy_pass ${autheliaAuthzURL};
            proxy_set_header X-Original-Method $request_method;
            proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header Content-Length "";
            proxy_set_header Connection "";
            proxy_pass_request_body off;
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
    };

    "p.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        root = pkgs.fetchFromGitHub {
          owner = "pschmitt";
          repo = "pschmitt.dev";
          rev = "b6d5e9cc361cede2756c81e5e9ce4f34c78b3824";
          hash = "sha256-w/BOiyBQIBsxlSdMhx0jx6Q0qKWHZQti0ayfLaBjINY=";
        };
      };
    };

    "y.${config.custom.mainDomain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        return = "301 https://raw.githubusercontent.com/pschmitt/yadm-init/main/init.sh";
      };
    };
  };
}
