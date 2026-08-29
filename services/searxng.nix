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
      "searxng/secret-key" = config.custom.mkSecret {
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
          # 0.0.0.0 (not just loopback) so the n8n container can reach it
          # directly over the trusted n8n docker bridge (see services/n8n.nix)
          # without going through the public limiter. Still not exposed to
          # the WAN: nginx is the only public path, and the firewall only
          # trusts the n8n bridge interface, not the world.
          bind_address = "0.0.0.0";
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
          # json is disabled by default on public instances; the Todoist
          # Emojifier n8n workflow needs it to search product images.
          # Public json access still runs through the botdetection limiter
          # above -- only the n8n bridge's passlisted IP is exempt from it.
          formats = [
            "html"
            "json"
          ];
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
        # NOT server.bind_address (0.0.0.0 -- a bind wildcard, not a valid
        # dial target). nginx always reaches searx over loopback.
        proxyPass = "http://127.0.0.1:${toString config.services.searx.settings.server.port}";
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
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
    '';
  };

  # The searx-init unit (services/searx module, upstream) always deletes any
  # limiter.toml on start, forcing the packaged default bot-detection, which
  # applies regardless of source interface -- our firewall trust for the n8n
  # bridge (services/n8n.nix) doesn't exempt it from the app-level limiter.
  # postStart runs after that deletion, in the same RuntimeDirectory=searx
  # unit (unlike searx.service, this one has no ReadOnlyPaths), and puts back
  # a copy with the n8n subnet passlisted for unrestricted API access.
  systemd.services.searx-init.postStart = ''
    umask 077
    cat > /run/searx/limiter.toml <<'EOF'
    [botdetection]
    ipv4_prefix = 32
    ipv6_prefix = 48
    trusted_proxies = [ '127.0.0.0/8', '::1' ]

    [botdetection.ip_limit]
    filter_link_local = false
    link_token = false

    [botdetection.ip_lists]
    block_ip = []
    # n8n docker bridge (br-n8n, see services/n8n.nix) -- unrestricted access
    # for the Todoist Emojifier's product-photo search.
    # Home Assistant (hv) reaches SearXNG over Tailscale for the AIS ship-photo
    # camera. fnuc is also trusted for local debugging. Keep these to the
    # explicit client addresses rather than bypassing the limiter for the whole
    # tailnet.
    pass_ip = [ '172.21.0.0/16', '100.84.129.3/32', '100.94.89.18/32' ]
    pass_searxng_org = true
    EOF
  '';
}
