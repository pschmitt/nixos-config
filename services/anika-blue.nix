{ config, ... }:
{
  sops.secrets."anika-blue/secretKey" = {
    sopsFile = config.custom.sopsFile;
  };

  services.anika-blue = {
    enable = true;
    debug = false;
    bindHost = "0.0.0.0";
    port = 26452;
    dataDir = "/var/lib/anika-blue";
    secretKeyFile = config.sops.secrets."anika-blue/secretKey".path;
  };

  services.nginx.virtualHosts =
    let
      nginxConfig = {
        enableACME = true;
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://${config.services.anika-blue.bindHost}:${toString config.services.anika-blue.port}";
          # proxyWebsockets = true;
          recommendedProxySettings = true;
        };

      };
    in
    {
      "anika-blue.${config.custom.mainDomain}" = nginxConfig;
      "anika-blue.bergmann-schmitt.de" = nginxConfig;
    };
}
