{
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/mnt/data/srv/stalwart/data";
  configFile = (pkgs.formats.json { }).generate "oci-01-stalwart-config.json" {
    "@type" = "Sqlite";
    path = "${dataDir}/database.sqlite";
    poolMaxConnections = 10;
  };
in
{
  security.acme.certs."mail.brkn.lol" = {
    group = "stalwart";
    reloadServices = [ "stalwart.service" ];
  };

  users.groups.stalwart.gid = 2000;
  users.users.stalwart = {
    uid = 2000;
    group = "stalwart";
    isSystemUser = true;
  };

  environment.etc."stalwart/config.json".source = configFile;

  systemd.tmpfiles.rules = [
    "d /etc/stalwart 0755 root root -"
    "d /etc/stalwart/certs 0755 root root -"
    "L+ /etc/stalwart/certs/mail.brkn.lol_ecc/fullchain.cer - - - - /var/lib/acme/mail.brkn.lol/fullchain.pem"
    "L+ /etc/stalwart/certs/mail.brkn.lol_ecc/mail.brkn.lol.key - - - - /var/lib/acme/mail.brkn.lol/key.pem"
  ];

  systemd.services.stalwart = {
    description = "Stalwart Mail Server";
    # Keep this disabled until the Compose project is stopped during cutover.
    wantedBy = [ ];
    wants = [
      "network-online.target"
      "acme-mail.brkn.lol.service"
    ];
    after = [
      "mnt-data.mount"
      "network-online.target"
      "acme-mail.brkn.lol.service"
    ];
    requires = [ "mnt-data.mount" ];
    unitConfig = {
      ConditionPathExists = [
        "${dataDir}/database.sqlite"
        "/etc/stalwart/config.json"
      ];
      RequiresMountsFor = [ dataDir ];
    };
    serviceConfig = {
      Type = "simple";
      User = "stalwart";
      Group = "stalwart";
      WorkingDirectory = dataDir;
      ExecStart = "${pkgs.stalwart_0_16}/bin/stalwart --config=/etc/stalwart/config.json";
      Restart = "on-failure";
      RestartSec = 5;
      LimitNOFILE = 65536;
      AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
      CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    };
  };

  networking.firewall.allowedTCPPorts = [
    25
    143
    465
    587
    993
    4190
  ];

  services.monit.config = lib.mkAfter ''
    check host "stalwart" with address "127.0.0.1"
      group services
      if failed
        port 8080
        protocol http
        with timeout 15 seconds
        for 3 cycles
      then alert
  '';
}
