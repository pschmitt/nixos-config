{ config, pkgs, ... }:
let
  domain = "changes.${config.domains.main}";
in
{
  services.changedetection-io = {
    enable = true;
    datastorePath = "/mnt/data/srv/changedetection-io";

    listenAddress = "localhost";
    port = 24264;
    behindProxy = false;

    webDriverSupport = false;
    playwrightSupport = !config.services.changedetection-io.webDriverSupport;
    baseURL = "https://${domain}";

    environmentFile = pkgs.writeText "changedetection-io.env" ''
      DISABLE_VERSION_CHECK=true
    '';
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
      };
    };
  };
}
