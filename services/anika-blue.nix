{ config, ... }:
{
  sops.secrets."anika-blue/secretKey" = {
    sopsFile = config.custom.sopsFile;
  };

  services.anika-blue = {
    enable = true;
    port = 5000;
    dataDir = "/var/lib/anika-blue";
    # Optional: path to file containing secret key
    # secretKeyFile = "/run/secrets/anika-blue-secret";
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
          proxyPass = "http://127.0.0.1:${toString config.services.anika-blue.port}";
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
