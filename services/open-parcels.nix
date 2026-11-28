{ config, ... }:
let
  host = "parcels.${config.domains.main}";
  port = 3097;
  dataDir = "/mnt/data/srv/open-parcels";
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir} 0700 1000 1000 - -" ];

  sops.secrets."open-parcels/reader-password" = config.sops.mkHostSecret { };
  sops.templates."open-parcels.env" = {
    content = ''
      OPENPARCELS_PASSWORD=${config.sops.placeholder."open-parcels/reader-password"}
    '';
    restartUnits = [
      "${config.virtualisation.oci-containers.containers.open-parcels.serviceName}.service"
    ];
  };

  virtualisation.oci-containers.containers.open-parcels = {
    image = "bluscream1/open-parcels:dev@sha256:a66247af6115d93ef79ee87fd67e6ccf9867bd5141941bdd117138b4a48335c4";
    ports = [ "127.0.0.1:${toString port}:3000" ];
    volumes = [
      "${dataDir}:/data"
      "${./scripts/open-parcels-dhl-mail.mjs}:/app/local-dhl-mail.mjs:ro"
    ];
    cmd = [
      "node"
      "--import=/app/local-dhl-mail.mjs"
      "server/dist/main.js"
    ];
    environmentFiles = [ config.sops.templates."open-parcels.env".path ];
    environment = {
      OPENPARCELS_PUBLIC_URL = "https://${host}";
      OPENPARCELS_SECURE_COOKIES = "true";
    };
    extraOptions = [
      "--read-only"
      "--tmpfs=/tmp"
      "--security-opt=no-new-privileges:true"
      "--cap-drop=ALL"
    ];
  };

  services.containerServices.services.open-parcels = {
    inherit port;
    hosts = [ host ];
    auth.enable = true;
    monitoring = {
      path = "/api/v1/health/ready";
      expectedHttpStatusCode = 200;
      restart.systemdUnit = config.virtualisation.oci-containers.containers.open-parcels.serviceName;
    };
  };
}
