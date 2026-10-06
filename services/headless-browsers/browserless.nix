{ config, ... }:
let
  hosts = config.domains.meshHosts "browserless";
  autheliaConfig = import ../authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
in
{
  virtualisation.oci-containers.containers.browserless = {
    # renovate: datasource=docker depName=ghcr.io/browserless/chromium
    image = "ghcr.io/browserless/chromium:latest@sha256:2c5ab1d430a07e53259f8dacfb290a1932ff14dba76dcb8ad0157d6a62bf4fa7";
    autoStart = true;
    log-driver = "none";
    ports = [ "127.0.0.1:3001:3000" ];
    environment = {
      CONCURRENT = "4";
      QUEUED = "8";
      # Interactive agent sessions can run long; one hour per connection.
      TIMEOUT = "3600000";
    };
    extraOptions = [
      "--init"
      "--shm-size=2g"
    ];
  };

  services.nginx.virtualHosts.${builtins.head hosts} = {
    serverAliases = builtins.tail hosts;
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    extraConfig = autheliaConfig.server;

    locations."= /" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location + ''
        # Land browser visitors on the dashboard; leave WebSocket clients that
        # connect to the bare host alone.
        if ($http_upgrade = "") {
          return 302 /debugger/;
        }

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };

    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = autheliaConfig.location + ''
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
