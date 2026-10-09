{ config, pkgs, ... }:
let
  hosts = config.domains.meshHosts "browserless";
  # A phone-friendly live view of one browser page (tap = click, drag = scroll,
  # a text box types into the focused field), used when an agent needs the user
  # to solve a CAPTCHA or enter a password: /handoff/?page=<page id>.
  handoff = pkgs.writeTextDir "index.html" (builtins.readFile ./handoff.html);
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
    forceSSL = true;
    authelia = {
      enable = true;
      haIngressBypass = false;
    };

    locations = {
      "= /" = {
        proxyPass = "http://127.0.0.1:3001";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          # Land browser visitors on the dashboard; leave WebSocket clients that
          # connect to the bare host alone.
          if ($http_upgrade = "") {
            return 302 /debugger/;
          }

          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };

      "/handoff/" = {
        alias = "${handoff}/";
      };

      "/" = {
        proxyPass = "http://127.0.0.1:3001";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };
  };
}
