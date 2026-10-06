{
  config,
  lib,
  pkgs,
  ...
}:
let
  nextcloudVersion = "35.0.1";
  nextcloudPort = 63982;
  nextcloudConfigDir = "/var/lib/nextcloud/native";
  nextcloudDataDir = "/srv/nextcloud/data/nextcloud";
  domain = config.domains.main;
  primaryHost = "c.${domain}";
  hostnames = [
    primaryHost
    "nextcloud.${domain}"
    "c.${config.networking.hostName}.${domain}"
    "nextcloud.${config.networking.hostName}.${domain}"
  ];
  serverAliases = lib.remove primaryHost hostnames;
  wildcardCert = "wildcard.${domain}";
in
{
  # The existing Compose data tree is owned by numeric GID 1000. Give that
  # group a system name and add it as a supplementary group for the upstream
  # NixOS service user; the service itself remains nextcloud:nextcloud.
  users.groups.nextcloud-data.gid = 1000;
  users.users.nextcloud.extraGroups = [ "nextcloud-data" ];

  systemd.tmpfiles.rules = [
    "d ${nextcloudConfigDir} 0750 nextcloud nextcloud - -"
    "z ${nextcloudConfigDir} 0750 nextcloud nextcloud - -"
    "d ${nextcloudConfigDir}/config 0750 nextcloud nextcloud - -"
    "z ${nextcloudConfigDir}/config 0750 nextcloud nextcloud - -"
    "z ${nextcloudConfigDir}/config/config.php 0640 nextcloud nextcloud - -"
    "d /var/lib/nextcloud/store-apps 0750 nextcloud nextcloud - -"
    "Z /var/lib/nextcloud/store-apps - nextcloud nextcloud - -"
  ];

  services = {
    nextcloud = {
      enable = true;
      hostName = primaryHost;
      https = true;
      datadir = nextcloudConfigDir;
      package = pkgs.nextcloud35.overrideAttrs (_old: {
        version = nextcloudVersion;
        src = pkgs.fetchurl {
          url = "https://download.nextcloud.com/server/releases/nextcloud-${nextcloudVersion}.tar.bz2";
          hash = "sha256-ftMF6IAZLYBLqDF5oZ3SIldnlgjWMWGmEc4/ipGNKqY=";
        };
      });
      fastcgiTimeout = 3600;
      database.createLocally = true;
      config = {
        dbtype = "pgsql";
        dbname = "nextcloud";
        dbuser = "nextcloud";
        adminuser = null;
      };
      settings = {
        datadirectory = nextcloudDataDir;
        dbpassword = null;
        trusted_domains = [
          primaryHost
          "cloud.${domain}"
          "nextcloud.${domain}"
          "nc.${domain}"
          "c.ovm5.de"
          "c.${config.networking.hostName}.${domain}"
          "nextcloud.${config.networking.hostName}.${domain}"
        ];
        trusted_proxies = [
          "127.0.0.0/8"
          "100.64.0.0/10"
        ];
        "overwrite.cli.url" = "https://${primaryHost}";
        default_phone_region = "DE";
        loglevel = 0;
      };
      extraApps = {
        inherit (pkgs.nextcloud35Packages.apps) contacts integration_paperless notes;
      };
      appstoreEnable = true;
    };

    # Calendar 6.6.1 is newer than the locked nixpkgs app (6.5.4). Its existing
    # code is copied into store-apps before the native service is enabled.
    # TODO: switch Calendar to pkgs.nextcloud35Packages.apps when nixpkgs catches up.

    nginx.virtualHosts.${primaryHost} = {
      inherit serverAliases;
      forceSSL = true;
      useACMEHost = wildcardCert;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::0]";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::0]";
          port = 443;
          ssl = true;
        }
        {
          addr = "127.0.0.1";
          port = nextcloudPort;
          ssl = true;
        }
      ];
    };

    monit.config = lib.mkAfter ''
      check host "nextcloud" with address "127.0.0.1"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart phpfpm-nextcloud.service"
        if failed
          port ${toString nextcloudPort}
          protocol https
          request "/status.php"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  systemd.services =
    lib.genAttrs
      [
        "nextcloud-setup"
        "nextcloud-cron"
        "nextcloud-update-db"
        "phpfpm-nextcloud"
      ]
      (_: {
        requires = [ "mnt-data.mount" ];
        after = [ "mnt-data.mount" ];
      });
}
