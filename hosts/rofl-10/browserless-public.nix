{ config, ... }:
let
  domain = config.domains.main;
  # The hosts running Browserless (profiles/headless-browsers.nix).
  browserHosts = [
    "fnuc"
    "rofl-13"
    "rofl-14"
  ];
  publicHost = host: "browser-${host}.${domain}";
  autheliaConfig = import ../../services/authelia-nginx-config.nix { inherit config; };

  # Public entry to the human-handoff view of a Browserless (see
  # services/headless-browsers/handoff.html), for when the user is away from the
  # mesh. *.${domain} already resolves to this host, which reaches the browser
  # hosts over the mesh. Browserless itself can run arbitrary browser code, so
  # ONLY what the handoff page needs is proxied: the page, its page list and the
  # CDP websocket of a single page. Everything else (/chromium, /function,
  # /sessions, ...) answers 404.
  vhost =
    host:
    let
      backendHost = "browserless.${host}.${config.domains.tailscale}";
      proxy = autheliaConfig.location + ''
        proxy_ssl_server_name on;
        proxy_set_header Host ${backendHost};
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    in
    {
      useACMEHost = "wildcard.${domain}";
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations = {
        "/handoff/" = {
          proxyPass = "https://${backendHost}";
          extraConfig = proxy;
        };
        "= /json/list" = {
          proxyPass = "https://${backendHost}";
          extraConfig = proxy;
        };
        "~ ^/devtools/page/[0-9A-Fa-f]+$" = {
          proxyPass = "https://${backendHost}";
          proxyWebsockets = true;
          extraConfig = proxy;
        };
        "/" = {
          extraConfig = autheliaConfig.location + ''
            return 404;
          '';
        };
      };
    };
  names = map publicHost browserHosts;
in
{
  services.nginx.virtualHosts = builtins.listToAttrs (
    map (host: {
      name = publicHost host;
      value = vhost host;
    }) browserHosts
  );

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
