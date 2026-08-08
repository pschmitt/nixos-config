# NOTE: nixpkgs also provides services.stalwart, but its current module is
# coupled to pkgs.stalwart (0.15.x). OCI-01's existing database was created
# and is still served by pkgs.stalwart_0_16, which nixpkgs explicitly marks as
# incompatible with that module. Keep this compatibility wrapper until the
# upstream module supports the 0.16 package or we perform an export/import
# migration between the two storage/configuration formats.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mainDomain = config.domains.main;
  mailHost = "mail.${mainDomain}";
  dkimSelector = "mail";
  dataDir = "/mnt/data/srv/stalwart/data";
  mailHealthCheck = pkgs.writeShellApplication {
    name = "stalwart-mail-health";
    runtimeInputs = [
      pkgs.bind
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.openssl
      pkgs.systemd
    ];
    text = builtins.readFile ./scripts/stalwart-mail-health.sh;
  };
  configFile = (pkgs.formats.json { }).generate "stalwart-config.json" {
    "@type" = "Sqlite";
    path = "${dataDir}/database.sqlite";
    poolMaxConnections = 10;
  };
in
{
  security.acme.certs."${mailHost}" = {
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
    "L+ /etc/stalwart/certs/${mailHost}_ecc/fullchain.cer - - - - /var/lib/acme/${mailHost}/fullchain.pem"
    "L+ /etc/stalwart/certs/${mailHost}_ecc/${mailHost}.key - - - - /var/lib/acme/${mailHost}/key.pem"
  ];

  systemd.services.stalwart = {
    description = "Stalwart Mail Server";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "acme-${mailHost}.service"
    ];
    after = [
      "mnt-data.mount"
      "network-online.target"
      "acme-${mailHost}.service"
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

    check host "stalwart-smtp" with address "127.0.0.1"
      group services
      if failed
        port 25
        with timeout 15 seconds
        for 3 cycles
      then alert

    check host "stalwart-submission" with address "127.0.0.1"
      group services
      if failed
        port 587
        with timeout 15 seconds
        for 3 cycles
      then alert

    check host "stalwart-smtps" with address "127.0.0.1"
      group services
      if failed
        port 465
        protocol smtps
        with timeout 15 seconds
        and certificate valid for 5 days
        for 3 cycles
      then alert

    check host "stalwart-imap" with address "127.0.0.1"
      group services
      if failed
        port 143
        protocol imap
        with timeout 15 seconds
        for 3 cycles
      then alert

    check host "stalwart-imaps" with address "127.0.0.1"
      group services
      if failed
        port 993
        protocol imaps
        with timeout 15 seconds
        and certificate valid for 5 days
        for 3 cycles
      then alert

    check host "stalwart-sieve" with address "127.0.0.1"
      group services
      if failed
        port 4190
        with timeout 15 seconds
        for 3 cycles
      then alert

    check program "stalwart-mail-health" with path "${mailHealthCheck}/bin/stalwart-mail-health ${mainDomain} ${dkimSelector}"
      group services
      if status != 0 then alert
  '';
}
