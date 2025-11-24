_:
let
  primaryHost = "vault.brkn.lol";
  serverAliases = [ "bw.brkn.lol" ];
  vaultwardenPort = 8222;
  websocketPort = 3012;
in
{
  services.vaultwarden = {
    enable = true;
    backupDir = "/srv/vaultwarden/backups";
    config = {
      DOMAIN = "https://${primaryHost}";
      SIGNUPS_ALLOWED = false;
      DATA_FOLDER = "/srv/vaultwarden/data";
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

  systemd.tmpfiles.rules = [
    "d /srv/vaultwarden 0750 vaultwarden vaultwarden -"
    "d /srv/vaultwarden/data 0750 vaultwarden vaultwarden -"
    "d /srv/vaultwarden/backups 0770 vaultwarden vaultwarden -"
  ];

  systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [ "/srv/vaultwarden" ];
}
