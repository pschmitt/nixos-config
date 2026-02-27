{
  config,
  lib,
  pkgs,
  ...
}:
let
  netboxHost = "netbox.${config.domains.main}";
in
{
  sops.secrets."netbox/secretKey" = {
    inherit (config.custom) sopsFile;
    owner = "netbox";
    group = "netbox";
    mode = "0400";
    restartUnits = [ "netbox.service" ];
  };

  services = {
    netbox = {
      enable = true;
      listenAddress = "127.0.0.1";
      dataDir = "/mnt/data/srv/netbox";
      secretKeyFile = config.sops.secrets."netbox/secretKey".path;
      plugins = python3Packages: with python3Packages; [ netbox-attachments ];
      settings = {
        ALLOWED_HOSTS = [
          netboxHost
          "127.0.0.1"
        ];
        PLUGINS = [ "netbox_attachments" ];
      };
    };

    nginx.virtualHosts."${netboxHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations = {
        "/static/" = {
          alias = "${config.services.netbox.dataDir}/static/";
        };
        "/" = {
          proxyPass = "http://${config.services.netbox.listenAddress}:${toString config.services.netbox.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };

    monit.config = lib.mkAfter ''
      check host "netbox" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart netbox.service netbox-rq.service"
        if failed
          port ${toString config.services.netbox.port}
          protocol http
          request "/"
          with hostheader "${netboxHost}"
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  users.users.nginx.extraGroups = [ "netbox" ];

  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules = [
    "d ${config.services.netbox.dataDir} 0750 netbox netbox - -"
    "Z ${config.services.netbox.dataDir} 0750 netbox netbox - -"
  ];
}
