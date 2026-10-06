{ config, ... }:
let
  browserlessHosts = config.domains.meshHosts "browserless";
  steelHosts = config.domains.meshHosts "steel";
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };

  browserVhost = port: hosts: {
    ${builtins.head hosts} = {
      serverAliases = builtins.tail hosts;
      enableACME = true;
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location + ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };
  };
in
{
  services.nginx.virtualHosts =
    (browserVhost 3001 browserlessHosts) // (browserVhost 3002 steelHosts);
}
