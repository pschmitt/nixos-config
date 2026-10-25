{ config, pkgs, ... }:
let
  domain = config.domains.main;
  # The hosts running browser-daemon (profiles/headless-browsers.nix).
  browserHosts = [
    "fnuc"
    "rofl-13"
    "rofl-14"
    "rofl-15"
  ];
  publicHost = host: "browser.${host}.${domain}";
  # Any browser-daemon: fnuc, or a rofl one while fnuc is down.
  anyHost = "browser.${domain}";
  anyMeshHosts = config.domains.meshHosts "browser";

  # NetBird: fnuc's Tailscale path loses packets under load (a 170 KB page
  # took ~3 s instead of ~0.3 s), which made screenshots crawl.
  backendHost = host: "browser.${host}.${config.domains.netbird}";
  # recommendedProxySettings is off on purpose: it would add a second Host
  # header (nginx on the browser host answers 400 to duplicates) and forward
  # the visitor's address, which would make the mesh host's own Authelia
  # check treat this already-authenticated request as an outside one.
  proxy = host: ''
    proxy_ssl_server_name on;
    proxy_set_header Host ${backendHost host};
    proxy_set_header X-Forwarded-For "";
    proxy_set_header X-Real-IP "";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  '';
  proxyLocation = host: {
    proxyPass = "https://${backendHost host}";
    proxyWebsockets = true;
    recommendedProxySettings = false;
    extraConfig = proxy host;
  };

  # Public entry to browser-daemon's dashboard and mobile handoff view,
  # for when the user is away from the mesh. The browser hosts (fnuc has no static
  # IP) are not exposed themselves: browser.<host>.${domain} (DNS records in
  # nixos-config-private's tofu) points at this host, which reaches them over the
  # mesh. Protected end-to-end by Authelia two-factor authentication.
  vhost = host: {
    # Two labels deep: not covered by the *.${domain} wildcard cert.
    enableACME = true;
    forceSSL = true;
    authelia.enable = true;
    locations = {
      "/" = proxyLocation host;
      "= /api/extension/config" = proxyLocation host // {
        authelia = false;
      };
      # The live view's extensions (its vault): static files of the daemon. Their
      # sandboxed frames load them as an opaque origin, without the Authelia
      # cookie, so they cannot be behind it.
      "^~ /handoff/ext/" = proxyLocation host // {
        authelia = false;
      };
      "= /api/extension/connect" = proxyLocation host // {
        # Only this socket authenticates its first frame with an origin-bound
        # browser credential. All dashboard/API routes retain Authelia.
        authelia = false;
      };
    };
  };

  # browser.${domain} goes through an upstream so nginx can fail over, but an
  # upstream has one Host header and SNI for all its servers, while each
  # browser host only answers to its own name. Hence a loopback hop per host
  # that sets them, as the vhosts above do.
  hopPort =
    host:
    {
      fnuc = 18081;
      "rofl-13" = 18082;
      "rofl-14" = 18083;
      "rofl-15" = 18084;
    }
    .${host};
  hop = host: {
    listen = [
      {
        addr = "127.0.0.1";
        port = hopPort host;
      }
    ];
    locations."/" = proxyLocation host // {
      extraConfig = proxy host + ''
        proxy_connect_timeout 3s;
      '';
    };
  };
  anyVhost = {
    forceSSL = true;
    authelia.enable = true;
    locations = {
      "= /api/extension/config" = {
        proxyPass = "http://browser_daemon";
        recommendedProxySettings = false;
        authelia = false;
      };
      # The live view's extensions (see the vhosts above).
      "^~ /handoff/ext/" = {
        proxyPass = "http://browser_daemon";
        recommendedProxySettings = false;
        authelia = false;
        extraConfig = "proxy_next_upstream error timeout http_502 http_503 http_504;";
      };
      "= /api/extension/connect" = {
        proxyPass = "http://browser_daemon";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        authelia = false;
        extraConfig = ''
          proxy_next_upstream error timeout http_502 http_503 http_504;
          proxy_read_timeout 60s;
          proxy_send_timeout 60s;
        '';
      };
      "/" = {
        proxyPass = "http://browser_daemon";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        # A request (or a new CDP connection) that reaches a host just going down
        # is retried on the next one rather than failing.
        extraConfig = ''
          proxy_next_upstream error timeout http_502 http_503 http_504;
          proxy_next_upstream_tries 3;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
      # Public share links of browser-daemon (/share/<node>/<token>[/<what>]):
      # no login, the daemon checks the token, and any node forwards to the one
      # in the link. Only these paths: the daemon's other pages hand out a
      # sign-in cookie and rely on Authelia here.
      "~ ^/share/[A-Za-z0-9_.-]+/[A-Za-z0-9_-]+(/[a-z]+)?$" = {
        proxyPass = "http://browser_daemon";
        recommendedProxySettings = false;
        authelia = false;
        extraConfig = ''
          proxy_next_upstream error timeout http_502 http_503 http_504;
          proxy_read_timeout 3600s;
        '';
      };
    };
  };
  names = map publicHost browserHosts ++ [ anyHost ];
in
{
  services.nginx = {
    # Active health checks, so a host that went down is skipped before a
    # request hits it (stock nginx only notices on live traffic).
    additionalModules = [ pkgs.nginxModules.upstream-check ];

    # fnuc first; the rofl hosts only while it is down. Sessions live on the
    # host that created them, so only new ones move: everything that names a
    # session or page (handoff, page sockets) uses the host's own name.
    upstreams.browser_daemon = {
      servers = builtins.listToAttrs (
        map (host: {
          name = "127.0.0.1:${toString (hopPort host)}";
          value = if host == "fnuc" then { } else { backup = true; };
        }) browserHosts
      );
      extraConfig = ''
        check interval=5000 rise=2 fall=2 timeout=5000 type=http;
        check_http_send "GET /health HTTP/1.0\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx;
      '';
    };

    virtualHosts =
      builtins.listToAttrs (
        map (host: {
          name = publicHost host;
          value = vhost host;
        }) browserHosts
      )
      // builtins.listToAttrs (
        map (host: {
          name = "browser-hop-${host}";
          value = hop host;
        }) browserHosts
      )
      // {
        ${anyHost} = anyVhost // {
          useACMEHost = "wildcard.${domain}";
        };
        # The mesh names are not covered by the wildcard cert (one label deep),
        # so they get their own DNS-01 cert. Authelia lets mesh clients through.
        ${builtins.head anyMeshHosts} = anyVhost // {
          serverAliases = builtins.tail anyMeshHosts;
          enableACME = true;
        };
      };
  };

  # Driving a logged-in browser is control-plane access: only the owner, with
  # two factors. The built-in rules before these still let mesh/local clients
  # through without a login, like every other service on this host.
  services.authelia.extraAccessControlRules = [
    {
      policy = "two_factor";
      domain = names;
      subject = [ "user:pschmitt" ];
    }
    {
      policy = "deny";
      domain = names;
    }
  ];
}
