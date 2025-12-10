{ config, pkgs, ... }:
let
  mealieHost = "nom.${config.domains.main}";
in
{
  sops = {
    secrets = {
      "mealie/openai-api-key" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "mealie.service" ];
      };
    };

    templates.mealieCredentials = {
      content = ''
        OPENAI_API_KEY=${config.sops.placeholder."mealie/openai-api-key"}
      '';
    };
  };

  services.mealie = {
    enable = true;
    package = pkgs.master.mealie;
    listenAddress = "127.0.0.1";
    port = 9000;
    credentialsFile = config.sops.templates.mealieCredentials.path;
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
