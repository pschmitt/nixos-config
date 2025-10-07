{ config, inputs, ... }:
{
  imports = [ inputs.poor-tools.nixosModules.default ];

  services.poor-installer-web = {
    enable = true;
  };

  services.nginx.virtualHosts =
    let
      nginxConfig = {
        enableACME = true;
        forceSSL = false; # disabled on purpose!
        addSSL = true; # required to actually response on https requests

        locations."/" = {
          proxyPass = "http://${toString config.services.poor-installer-web.bindHost}:${toString config.services.poor-installer-web.bindPort}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    in
    {
      "poor.tools" = nginxConfig;
      "poor.curl-pipe.sh" = nginxConfig;
      "poor.${config.custom.mainDomain}" = nginxConfig;
    };
}
