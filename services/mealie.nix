{ config, pkgs, ... }:
let
  mealieHost = "nom.${config.domains.main}";
  mealiePort = 63254;
  # renovate: datasource=docker depName=ghcr.io/mealie-recipes/mealie
  mealieVersion = "v3.9.2";
in
{
  sops.secrets."mealie/openai-api-key" = {
    inherit (config.custom) sopsFile;
    restartUnits = [ "${config.virtualisation.oci-containers.backend}-mealie.service" ];
  };

  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:${mealieVersion}";
    autoStart = true;
    ports = [
      "127.0.0.1:${toString mealiePort}:9000"
    ];
    volumes = [
      "/srv/mealie/data/mealie:/app/data"
    ];
    environment = {
      ALLOW_SIGNUP = "false";
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      BASE_URL = "https://${mealieHost}";
    };
    environmentFiles = [
      config.sops.secrets."mealie/openai-api-key".path
    ];
    # extraOptions = [
    #   "--memory=1000m"
    # ];
  };

  # services.mealie = {
  #   enable = true;
  #   package = pkgs.master.mealie;
  #   listenAddress = "127.0.0.1";
  #   port = 9000;
  #   credentialsFile = config.sops.templates.mealieCredentials.path;
  # };

  services.nginx.virtualHosts."${mealieHost}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString mealiePort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = ''
    check host "mealie" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-mealie.service"
        with timeout 180 seconds
      if failed
        port ${toString mealiePort}
        protocol http
        with timeout 90 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
