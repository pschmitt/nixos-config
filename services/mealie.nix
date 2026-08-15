{ config, pkgs, ... }:
let
  mealieHost = "nom.${config.domains.main}";
  mealiePort = 63254;
  syncwichAssetLinks = pkgs.writeText "syncwich-assetlinks.json" (
    builtins.toJSON [
      {
        relation = [ "delegate_permission/common.handle_all_urls" ];
        target = {
          namespace = "android_app";
          package_name = "dev.pschmitt.syncwich";
          sha256_cert_fingerprints = [
            "AE:03:2C:4E:C7:0B:D1:8E:29:48:3A:87:85:1A:F0:1A:DC:9F:D0:CF:48:E7:E8:4B:8A:54:7C:64:DF:47:21:A4"
          ];
        };
      }
    ]
  );
  # renovate: datasource=docker depName=ghcr.io/mealie-recipes/mealie
  mealieVersion = "v3.22.0";
in
{
  sops.secrets."mealie/openai-api-key" = config.custom.mkSecret {
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

    locations."= /.well-known/assetlinks.json" = {
      alias = syncwichAssetLinks;
      extraConfig = ''
        default_type application/json;
        add_header Cache-Control "public, max-age=3600" always;
      '';
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
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
  '';
}
