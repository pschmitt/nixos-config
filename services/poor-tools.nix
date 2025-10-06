{ config, inputs, ... }: {
  imports = [ inputs.poor-tools.nixosModules.default ];

  services.poor-tools-web = {
    enable = true;
  };

  services.nginx.virtualHosts."poor.curl-pipe.sh" = {
    enableACME = true;
    forceSSL = false; # disabled on purpose!

    locations."/" = {
      proxyPass = "http://${toString config.services.poor-tools-web.bindHost}:${toString config.services.poor-tools-web.bindPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
