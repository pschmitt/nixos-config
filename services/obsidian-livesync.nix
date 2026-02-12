{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = "obsidian.${config.domains.main}";
  listenPort = 35984;
in
{
  sops = {
    secrets = {
      "obsidian-livesync/username" = {
        inherit (config.custom) sopsFile;
      };
      "obsidian-livesync/password" = {
        inherit (config.custom) sopsFile;
      };
    };

    templates."obsidian-livesync/admin.ini" = {
      content = ''
        [admins]
        ${config.sops.placeholder."obsidian-livesync/username"} = ${
          config.sops.placeholder."obsidian-livesync/password"
        }
      '';
      owner = config.services.couchdb.user;
      inherit (config.services.couchdb) group;
      mode = "0440";
      restartUnits = [ "couchdb.service" ];
    };
  };

  services = {
    couchdb = {
      enable = true;
      bindAddress = "127.0.0.1";
      port = listenPort;
      extraConfig = {
        couchdb = {
          single_node = "true";
          max_document_size = "5000000000"; # 500MB
        };
        chttpd = {
          require_valid_user = "true";
          enable_cors = "true";
          max_http_request_size = "4294967296";
        };
        chttpd_auth = {
          require_valid_user = "true";
          authentication_redirect = "/_utils/session.html";
        };
        httpd = {
          WWW-Authenticate = ''Basic realm="couchdb"'';
        };
        cors = {
          origins = "app://obsidian.md,capacitor://localhost,http://localhost,https://${host}";
          credentials = "true";
          methods = "GET, PUT, POST, HEAD, DELETE";
          headers = "accept, authorization, content-type, origin, referer";
          max_age = "3600";
        };
      };
      extraConfigFiles = [ config.sops.templates."obsidian-livesync/admin.ini".path ];
    };

    nginx.virtualHosts."${host}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString listenPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "obsidian-livesync" with address "127.0.0.1"
        group container-services
        restart program = "${pkgs.systemd}/bin/systemctl restart couchdb.service"
        if failed
          port ${toString listenPort}
          protocol http
          request "/"
          status 401
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
