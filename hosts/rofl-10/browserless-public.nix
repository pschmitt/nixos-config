{ config, ... }:
let
  domain = config.domains.main;
  # The hosts running Browserless (profiles/headless-browsers.nix).
  browserHosts = [
    "fnuc"
    "rofl-13"
    "rofl-14"
  ];
  publicHost = host: "browser.${host}.${domain}";

  # Public entry to browser-daemon's dashboard and mobile handoff view,
  # for when the user is away from the mesh. The browser hosts (fnuc has no static
  # IP) are not exposed themselves: browser.<host>.${domain} (DNS records in
  # nixos-config-private's tofu) points at this host, which reaches them over the
  # mesh. Protected end-to-end by Authelia two-factor authentication.
  vhost =
    host:
    let
      backendHost = "browserless.${host}.${config.domains.tailscale}";
      # recommendedProxySettings is off on purpose: it would add a second Host
      # header (nginx on the browser host answers 400 to duplicates) and forward
      # the visitor's address, which would make the mesh host's own Authelia
      # check treat this already-authenticated request as an outside one.
      proxy = ''
        proxy_ssl_server_name on;
        proxy_set_header Host ${backendHost};
        proxy_set_header X-Forwarded-For "";
        proxy_set_header X-Real-IP "";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    in
    {
      # Two labels deep: not covered by the *.${domain} wildcard cert.
      enableACME = true;
      forceSSL = true;
      authelia.enable = true;
      locations = {
        "/" = {
          proxyPass = "https://${backendHost}";
          proxyWebsockets = true;
          recommendedProxySettings = false;
          extraConfig = proxy;
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
