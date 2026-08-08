# NOTE: Use the upstream services.stalwart module for the account, tmpfiles,
# hardening, and systemd service. Its generated TOML is for pkgs.stalwart
# 0.15.x, while this host's existing database is served by pkgs.stalwart_0_16
# and requires the upstream JSON datastore bootstrap. Keep only that narrow
# compatibility override until the module supports the 0.16 configuration.
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
  mailPortChecks = [
    {
      name = "smtp";
      port = 25;
    }
    {
      name = "submission";
      port = 587;
    }
    {
      name = "smtps";
      port = 465;
      protocol = "smtps";
      tls = true;
    }
    {
      name = "imap";
      port = 143;
      protocol = "imap";
    }
    {
      name = "imaps";
      port = 993;
      protocol = "imaps";
      tls = true;
    }
    {
      name = "sieve";
      port = 4190;
    }
  ];
  mkMailPortCheck =
    {
      name,
      port,
      protocol ? null,
      tls ? false,
    }:
    ''
      check host "stalwart-${name}" with address "127.0.0.1"
        group mail
        group services
        depends on "stalwart"
        if failed
          port ${toString port}
          ${lib.optionalString (protocol != null) "protocol ${protocol}\n        "}with timeout 15 seconds
          ${lib.optionalString tls "and certificate valid for 5 days\n        "}for 3 cycles
        then alert
    '';
  mailPortChecksConfig = lib.concatStringsSep "\n" (map mkMailPortCheck mailPortChecks);
  mailHealthCheck = pkgs.writeShellApplication {
    name = "stalwart-mail-health";
    runtimeInputs = [
      pkgs.dnsutils
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.openssl
      pkgs.systemd
    ];
    text = builtins.readFile ./scripts/stalwart-mail-health.sh;
  };
  bootstrapConfig = (pkgs.formats.json { }).generate "stalwart-config.json" {
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

  services.stalwart = {
    enable = true;
    package = pkgs.stalwart_0_16;
    stateVersion = "26.11";
    inherit dataDir;
    user = "stalwart";
    group = "stalwart";
  };

  # The module creates this account; retain the IDs used by the existing data.
  users.groups.stalwart.gid = 2000;
  users.users.stalwart.uid = 2000;

  environment.etc."stalwart/config.json".source = bootstrapConfig;

  systemd.tmpfiles.rules = [
    "d /etc/stalwart 0755 root root -"
    "d /etc/stalwart/certs 0755 root root -"
    "L+ /etc/stalwart/certs/${mailHost}_ecc/fullchain.cer - - - - /var/lib/acme/${mailHost}/fullchain.pem"
    "L+ /etc/stalwart/certs/${mailHost}_ecc/${mailHost}.key - - - - /var/lib/acme/${mailHost}/key.pem"
  ];

  # The upstream module owns this unit. Only replace its incompatible TOML
  # command and storage preparation with the existing 0.16 JSON bootstrap.
  systemd.services.stalwart = {
    after = [
      "mnt-data.mount"
      "network-online.target"
      "acme-${mailHost}.service"
    ];
    requires = [ "mnt-data.mount" ];
    wants = [
      "network-online.target"
      "acme-${mailHost}.service"
    ];
    unitConfig = {
      ConditionPathExists = lib.mkForce [
        "${dataDir}/database.sqlite"
        "/etc/stalwart/config.json"
      ];
      RequiresMountsFor = [ dataDir ];
    };
    serviceConfig = {
      WorkingDirectory = dataDir;
      ExecStartPre = lib.mkForce [ ];
      ExecStart = lib.mkForce [
        ""
        "${pkgs.stalwart_0_16}/bin/stalwart --config=/etc/stalwart/config.json"
      ];
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
      group mail
      group services
      if failed
        port 8080
        protocol http
        with timeout 15 seconds
        for 3 cycles
      then alert

    ${mailPortChecksConfig}

    check program "stalwart-mail-health" with path "${mailHealthCheck}/bin/stalwart-mail-health ${mainDomain} ${dkimSelector}"
      group mail
      group services
      depends on "stalwart"
      if status != 0 then alert
  '';
}
