{
  config,
  lib,
  ...
}:
let
  hostnames = [ "paperless.${config.networking.hostName}.${config.custom.mainDomain}" ];
  hostnamesWithSchema = map (host: "https://${host}") hostnames;
in
{
  sops.secrets."paperless-ngx/adminPassword" = {
    sopsFile = config.custom.sopsFile;
  };

  # FIXME THIS LOCKS THE FUCKING ROOT USER WHEN APPLIED
  # boot.supportedFilesystems = [ "bindfs" ];
  # system.fsPackages = [ pkgs.bindfs ];
  # fileSystems."${config.services.paperless.consumptionDir}" = {
  #   device = "/mnt/data/srv/nextcloud/data/nextcloud/pschmitt/files/Documents";
  #   fsType = "bindfs";
  #   options = [
  #     "user=${config.services.paperless.user}"
  #     "group=${config.services.paperless.user}"
  #   ];
  # };

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

      PAPERLESS_FILENAME_FORMAT = "{original_name}";
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
            locations."/" = {
              proxyPass = "http://${config.services.paperless.address}:${toString config.services.paperless.port}";
              proxyWebsockets = true;
              recommendedProxySettings = true;
            };
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };

  users.users."${config.custom.username}" = {
    extraGroups = [ "paperless" ];
  };

  # Override default tmpfile settings
  # The ones provided by the module are not working too well.
  systemd.tmpfiles.settings."10-paperless" =
    let
      user = config.services.paperless.user;

      defaultRule = {
        user = user;
        group = user;
        mode = "755"; # enforce mode for all dirs
      };
    in
    {
      "${config.services.paperless.dataDir}".d = defaultRule;
      "${config.services.paperless.mediaDir}".d = defaultRule;
      "${config.services.paperless.consumptionDir}".d = defaultRule;
    };
}
