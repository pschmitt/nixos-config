{ config, pkgs, ... }:
let
  mealieHost = "nom.${config.custom.mainDomain}";
in
{
  sops = {
    secrets = {
      "mealie/openai-api-key" = {
        sopsFile = config.custom.sopsFile;
        restartUnits = [ "mealie" ];
      };
    };

    templates.mealieCredentials = {
      # owner = "mealie";
      content = ''
        OPENAI_API_KEY=${config.sops.placeholder."mealie/openai-api-key"}
      '';
    };
  };

  # systemd.services.mealie = {
  #   serviceConfig = {
  #     # Group = "mealie";
  #     LoadCredential = [ "openai_api_key:${config.sops.secrets."mealie/openai-api-key".path}" ];
  #     Environment = [ "OPENAI_API_KEY=%d/openai_api_key" ];
  #   };
  # };

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
