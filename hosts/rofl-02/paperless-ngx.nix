{ config, lib, ... }:
let
  hostnames = [
    "paperless.${config.networking.hostName}.brkn.lol"
    "paperless.${config.networking.hostName}.heimat.dev"
  ];
  hostnamesWithSchema = map (host: "https://${host}") hostnames;
in
{
  sops.secrets."paperless-ngx/adminPassword" = {
    sopsFile = config.custom.sopsFile;
  };

  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    port = 28981;

    dataDir = "/mnt/data/srv/paperless-ngx/data";
    mediaDir = "/mnt/data/srv/paperless-ngx/data/media";
    consumptionDir = "/mnt/data/srv/paperless-ngx/data/consume";
    consumptionDirIsPublic = false;

    # https://docs.paperless-ngx.com/configuration/
    settings = {
      PAPERLESS_ADMIN_USER = config.custom.username;

      PAPERLESS_ALLOWED_HOSTS = lib.concatStringsSep "," hostnames;
      PAPERLESS_CORS_ALLOWED_HOSTS = lib.concatStringsSep "," hostnamesWithSchema;
      PAPERLESS_CSRF_TRUSTED_ORIGINS = lib.concatStringsSep "," hostnamesWithSchema;

      PAPERLESS_OCR_LANGUAGE = "deu+fra+eng";
      PAPERLESS_CONSUMER_RECURSIVE = true;
    };
    passwordFile = config.sops.secrets."paperless-ngx/adminPassword".path;
  };

  # networking.firewall.allowedTCPPorts = [ 28981 ];

  services.nginx =
    let
      virtualHosts = builtins.listToAttrs (
        map (hostname: {
          name = hostname;
          value = {
            enableACME = true;
            # FIXME https://github.com/NixOS/nixpkgs/issues/210807
            acmeRoot = null;
            forceSSL = true;
            locations."/".extraConfig = ''
              proxy_pass http://127.0.0.1:${toString config.services.paperless.port};
              proxy_set_header Host $host;
              proxy_redirect http:// https://;
              # proxy_http_version 1.1;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
            '';
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}