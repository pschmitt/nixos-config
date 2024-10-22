{ config, ... }:
let
  domain = "changes.${config.custom.mainDomain}";
in
{
  services.changedetection-io = {
    enable = true;

    listenAddress = "localhost";
    port = 24264;
    behindProxy = false;

    webDriverSupport = true;
    playwrightSupport = !config.services.changedetection-io.webDriverSupport;
    baseURL = "https://${domain}";
  };

  sops.secrets = {
    "changedetection-io/htpasswd" = {
      sopsFile = config.custom.sopsFile;
      owner = "nginx";
    };
  };

  services.nginx.virtualHosts = {
    "${domain}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://${config.services.changedetection-io.listenAddress}:${toString config.services.changedetection-io.port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        basicAuthFile = config.sops.secrets."changedetection-io/htpasswd".path;
      };
    };
  };
}
