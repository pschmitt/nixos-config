{ config, ... }:
let
  domain = "search.${config.custom.mainDomain}";
in
{
  sops = {
    secrets = {
      "searxng/secret-key" = {
        sopsFile = config.custom.sopsFile;
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

  services.searx = {
    enable = true;
    redisCreateLocally = true;
    environmentFile = config.sops.templates.searxngEnvFile.path;
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 7372;
      };
      general = {
        debug = false;
        instance_name = "SearXNG@brkn.lol";
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

  services.nginx.virtualHosts."${domain}" = {
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
}
