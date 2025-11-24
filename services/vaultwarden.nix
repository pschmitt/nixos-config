{ lib, ... }:
let
  primaryHost = "vault.brkn.lol";
  serverAliases = [ "bw.brkn.lol" ];
  vaultwardenPort = 8222;
  websocketPort = 3012;

  rootDir = "/srv/vaultwarden";
  dataDir = "${rootDir}/data";
  backupDir = "${rootDir}/backups";
in
{
  services.vaultwarden = {
    enable = true;
    inherit backupDir;
    config = {
      DOMAIN = "https://${primaryHost}";
      SIGNUPS_ALLOWED = lib.mkForce false;
      DATA_FOLDER = dataDir;
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      WEBSOCKET_ENABLED = true;
      WEBSOCKET_ADDRESS = "127.0.0.1";
      WEBSOCKET_PORT = websocketPort;
    };
  };

  services.nginx.virtualHosts.${primaryHost} = {
    inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:${toString vaultwardenPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      "/notifications/hub" = {
        proxyPass = "http://127.0.0.1:${toString websocketPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      "/notifications/hub/negotiate" = {
        proxyPass = "http://127.0.0.1:${toString vaultwardenPort}";
        recommendedProxySettings = true;
      };
    };
  };

  systemd = {
    tmpfiles.rules = [
      "d ${rootDir}   0750 vaultwarden vaultwarden -"
      "d ${dataDir}   0750 vaultwarden vaultwarden -"
      "d ${backupDir} 0770 vaultwarden vaultwarden -"
    ];

    services.vaultwarden.serviceConfig.ReadWritePaths = [ rootDir ];

    # Ensure built-in backup service uses the custom data dir.
    services.backup-vaultwarden.environment.DATA_FOLDER = lib.mkForce dataDir;
  };
}
