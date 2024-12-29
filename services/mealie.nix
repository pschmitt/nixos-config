{ config, pkgs, ... }:
let
  mealieHost = "nom.${config.custom.mainDomain}";
in
{
  services.mealie = {
    enable = true;
    package = pkgs.master.mealie;
    listenAddress = "127.0.0.1";
    port = 9000;
  };

  services.nginx.virtualHosts."${mealieHost}" = {
    enableACME = true;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://${toString config.services.mealie.listenAddress}:${toString config.services.mealie.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
