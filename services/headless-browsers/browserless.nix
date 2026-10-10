{ config, ... }:
let
  browserlessHosts = config.domains.meshHosts "browserless";
  browserHosts = config.domains.meshHosts "browser";
  hosts = browserlessHosts ++ browserHosts;
  meshNodes = [
    "fnuc"
    "rofl-13"
    "rofl-14"
  ];
in
{
  services = {
    browser-daemon = {
      enable = true;
      bind = "127.0.0.1:3001";
      maxSessions = 8;
      nodeName = config.networking.hostName;
      publicUrl = "https://browser.${config.networking.hostName}.${config.domains.tailscale}";
      peers = map (h: "https://browser.${h}.${config.domains.tailscale}") meshNodes;
    };

    nginx.virtualHosts.${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      forceSSL = true;
      authelia = {
        enable = true;
        haIngressBypass = false;
      };

      locations."/" = {
        proxyPass = "http://127.0.0.1:3001";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    monit.checks.browser-daemon = {
      type = "host";
      address = "127.0.0.1";
      group = "services";
      restartUnit = "browser-daemon.service";
      conditions = ''
        if failed
          port 3001
          protocol http
          request "/health"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 15 cycles then alert
      '';
    };
  };
}
