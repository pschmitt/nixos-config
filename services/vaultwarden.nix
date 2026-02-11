{
  config,
  lib,
  pkgs,
  ...
}:
let
  primaryHost = "vault.${config.domains.main}";
  serverAliases = [ "bw.${config.domains.main}" ];
  vaultwardenPort = 8222;
  websocketPort = 3012;

  rootDir = "/srv/vaultwarden";
  dataDir = "${rootDir}/data";
  backupDir = "${rootDir}/backups";
  vaultwardenUser = "vaultwarden";
  secretAttrs = {
    inherit (config.custom) sopsFile;
    owner = vaultwardenUser;
    group = vaultwardenUser;
    mode = "0400";
    restartUnits = [ "vaultwarden.service" ];
  };
in
{
  sops = {
    secrets = {
      "vaultwarden/smtp/host" = secretAttrs;
      "vaultwarden/smtp/port" = secretAttrs;
      "vaultwarden/smtp/security" = secretAttrs;
      "vaultwarden/smtp/username" = secretAttrs;
      "vaultwarden/smtp/password" = secretAttrs;
      "vaultwarden/smtp/from" = secretAttrs;
    };

    templates."vaultwarden/smtp.env" = {
      content = ''
        SMTP_FROM="${config.sops.placeholder."vaultwarden/smtp/from"}"
        SMTP_HOST="${config.sops.placeholder."vaultwarden/smtp/host"}"
        SMTP_PORT="${toString config.sops.placeholder."vaultwarden/smtp/port"}"
        SMTP_SECURITY="${config.sops.placeholder."vaultwarden/smtp/security"}"
        SMTP_USERNAME="${config.sops.placeholder."vaultwarden/smtp/username"}"
        SMTP_PASSWORD="${config.sops.placeholder."vaultwarden/smtp/password"}"
      '';
      owner = vaultwardenUser;
      group = vaultwardenUser;
      mode = "0400";
      restartUnits = [ "vaultwarden.service" ];
    };
  };

  services = {
    vaultwarden = {
      enable = true;
      # NOTE we need vaultwarden 1.35.3+ for the bw cli to be able to connect to
      # the server, which is required for the bw-sync service.
      package = pkgs.master.vaultwarden;
      inherit backupDir;
      environmentFile = config.sops.templates."vaultwarden/smtp.env".path;
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

    nginx.virtualHosts.${primaryHost} = {
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

    monit.config = lib.mkAfter ''
      check host "vaultwarden" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart vaultwarden.service"
        if failed
          port ${toString vaultwardenPort}
          protocol http
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  systemd = {
    tmpfiles.rules =
      let
        user = config.systemd.services.vaultwarden.serviceConfig.User;
        group = config.systemd.services.vaultwarden.serviceConfig.Group;
      in
      [
        "d ${rootDir}   0750 ${user} ${group} -"
        "d ${dataDir}   0750 ${user} ${group} -"
        "d ${backupDir} 0770 ${user} ${group} -"
        # Fix permissions after UID changes (e.g., after reinstall)
        "Z ${rootDir}   0750 ${user} ${group} - -"
      ];

    services = {
      vaultwarden.serviceConfig.ReadWritePaths = [ rootDir ];

      # Ensure built-in backup service uses the custom data dir.
      backup-vaultwarden.environment.DATA_FOLDER = lib.mkForce dataDir;
    };
  };
}
