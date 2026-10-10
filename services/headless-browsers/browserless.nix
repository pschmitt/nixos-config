{ config, pkgs, ... }:
let
  hosts = config.domains.meshHosts "browserless";
  # A phone-friendly live view of one browser page (tap = click, drag = scroll,
  # a text box types into the focused field), used when an agent needs the user
  # to solve a CAPTCHA or enter a password: /handoff/?page=<page id>.
  handoff = pkgs.writeTextDir "index.html" (builtins.readFile ./handoff.html);
in
{
  services = {
    browser-daemon = {
      enable = true;
      bind = "127.0.0.1:3001";
      maxSessions = 8;
    };

    nginx.virtualHosts.${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      forceSSL = true;
      authelia = {
        enable = true;
        haIngressBypass = false;
      };

      locations = {
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
