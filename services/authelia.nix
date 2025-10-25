{ config, lib, ... }:
let
  instanceName = "main";
  autheliaDomain = "auth.${config.custom.mainDomain}";
  autheliaUser = "authelia-${instanceName}";
  autheliaGroup = autheliaUser;
  autheliaService = "authelia-${instanceName}.service";
  stateDir = "/var/lib/${autheliaUser}";
  secretsAttrs = owner: {
    sopsFile = config.custom.sopsFile;
    inherit owner;
    group = autheliaGroup;
    mode = "0400";
    restartUnits = [ autheliaService ];
  };
  bypassNetworks = [
    "127.0.0.1/32"
    "::1/128"
    "100.64.0.0/10"
  ];

  autheliaSettings = {
    session.cookies = [
      {
        domain = config.custom.mainDomain;
        authelia_url = "https://${autheliaDomain}";
      }
    ];
    authentication_backend.file = {
      path = config.sops.secrets."authelia/users-database".path;
      watch = false;
    };
    storage.local.path = "${stateDir}/db.sqlite3";
    notifier.filesystem.filename = "${stateDir}/notification.txt";
    access_control = {
      default_policy = "one_factor";
      networks = [
        {
          name = "local";
          networks = bypassNetworks;
        }
      ];
      rules = [
        {
          policy = "bypass";
          domain = [ autheliaDomain ];
        }
        {
          policy = "bypass";
          networks = [ "local" ];
          domain = [ "*.${config.custom.mainDomain}" ];
        }
      ];
    };
  };
in
{
  sops.secrets = {
    "authelia/jwt-secret" = secretsAttrs autheliaUser;
    "authelia/storage-encryption-key" = secretsAttrs autheliaUser;
    "authelia/users-database" = secretsAttrs autheliaUser;
  };

  services.authelia.instances.${instanceName} = {
    enable = true;
    user = autheliaUser;
    group = autheliaGroup;
    secrets = {
      jwtSecretFile = config.sops.secrets."authelia/jwt-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."authelia/storage-encryption-key".path;
    };
    settings = autheliaSettings;
  };

  services.nginx.virtualHosts.${autheliaDomain} = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:9091/";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
