{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "search.${config.domains.main}";
in
{
  sops = {
    secrets = {
      "searxng/secret-key" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "searx.service" ];
      };
    };
    templates.searxngEnvFile = {
      owner = "searx";
      # mode = "0400";
      restartUnits = [ "searx.service" ];
      content = ''
        SEARXNG_SECRET=${config.sops.placeholder."searxng/secret-key"}
      '';
    };
  };

  services = {
    searx = {
      enable = true;
      redisCreateLocally = true;
      environmentFile = config.sops.templates.searxngEnvFile.path;
      settings = {
        server = {
          bind_address = "127.0.0.1";
          port = 7372;
          public_instance = true;
          limiter = true;
          image_proxy = true;
        };
        general = {
          debug = false;
          instance_name = "SearXNG@${config.domains.main}";
          donation_url = false;
          contact_url = false;
          privacypolicy_url = false;
          enable_metrics = false;
        };
        search = {
          autcomplete = "google";
          # https://docs.searxng.org/admin/searx.favicons.html
          favicon_resolver = "duckduckgo";
          safe_search = 0; # 0: off, 1: moderate, 2: strict
        };
        ui = {
          query_in_title = true;
          infinite_scroll = true;
          search_on_category_select = true;
          hotkeys = "vim";
          url_formatting = "pretty"; # pretty, full or host
        };
      };
    };

    # systemd.services.nginx.serviceConfig.ProtectHome = false;
    # users.groups.searx.members = [ "nginx" ];

    nginx.virtualHosts."${domain}" = {
      forceSSL = true;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;

      locations."/" = {
        proxyPass = "http://${config.services.searx.settings.server.bind_address}:${toString config.services.searx.settings.server.port}";
        # proxyPass = "http://127.0.0.1:7372";
        recommendedProxySettings = true;
        proxyWebsockets = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "searxng" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart searx.service"
        if failed
          port ${toString config.services.searx.settings.server.port}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
