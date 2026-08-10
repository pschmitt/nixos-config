# NOTE: Use the upstream services.stalwart module for the account, tmpfiles,
# hardening, and systemd service. Its generated TOML is for pkgs.stalwart
# 0.15.x, while this host's existing database is served by pkgs.stalwart_0_16
# and requires the upstream JSON datastore bootstrap. The custom Stalwart
# module reconciles the database-backed listener objects from Nix.
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
  stalwartListeners = {
    http = {
      bind = [
        "0.0.0.0:8080"
        "[::]:8080"
      ];
      protocol = "http";
    };
    smtp = {
      bind = [
        "0.0.0.0:25"
        "[::]:25"
      ];
      protocol = "smtp";
    };
    submission = {
      bind = [
        "0.0.0.0:587"
        "[::]:587"
      ];
      protocol = "smtp";
    };
    smtps = {
      bind = [
        "0.0.0.0:465"
        "[::]:465"
      ];
      protocol = "smtp";
    };
    imap = {
      bind = [
        "0.0.0.0:143"
        "[::]:143"
      ];
      protocol = "imap";
    };
    imaps = {
      bind = [
        "0.0.0.0:993"
        "[::]:993"
      ];
      protocol = "imap";
    };
    sieve = {
      bind = [
        "0.0.0.0:4190"
        "[::]:4190"
      ];
      protocol = "manageSieve";
    };
  };
  listenerPort =
    name:
    let
      listener = builtins.getAttr name config.services.stalwart.settings.server.listener;
      address = builtins.head listener.bind;
    in
    lib.toInt (lib.last (lib.splitString ":" address));
  mailPortChecks = [
    {
      name = "smtp";
      listener = "smtp";
    }
    {
      name = "submission";
      listener = "submission";
    }
    {
      name = "smtps";
      listener = "smtps";
      protocol = "smtps";
      tls = true;
    }
    {
      name = "imap";
      listener = "imap";
      protocol = "imap";
    }
    {
      name = "imaps";
      listener = "imaps";
      protocol = "imaps";
      tls = true;
    }
    {
      name = "sieve";
      listener = "sieve";
    }
  ];
  mkMailPortCheck =
    {
      name,
      listener,
      protocol ? null,
      tls ? false,
    }:
    ''
      check host "stalwart-${name}" with address "127.0.0.1"
        group mail
        group services
        depends on "stalwart"
        if failed
          port ${toString (listenerPort listener)}
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
  dnsReconcile = pkgs.writeShellApplication {
    name = "stalwart-dns-reconcile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.stalwart-cli
    ];
    text = builtins.readFile ./scripts/stalwart-dns-reconcile.sh;
  };
  listenerObjectName = {
    imap = "imap-starttls";
    smtps = "submissions";
  };
  desiredNetworkListeners = lib.mapAttrs (
    name: listener:
    listener
    // {
      name = listenerObjectName.${name} or name;
      tlsImplicit = builtins.elem name [
        "imaps"
        "smtps"
      ];
    }
  ) stalwartListeners;
  datastoreBootstrap = (pkgs.formats.json { }).generate "stalwart-config.json" {
    "@type" = "Sqlite";
    path = "${dataDir}/database.sqlite";
    poolMaxConnections = 10;
  };
in
{
  security.acme.certs."${mailHost}" = {
    group = config.services.stalwart.group;
    reloadServices = [ "stalwart.service" ];
  };

  services.stalwart = {
    enable = true;
    package = pkgs.stalwart_0_16;
    stateVersion = "26.11";
    inherit dataDir;
    openFirewall = true;
    settings.server.listener = stalwartListeners;
  };

  custom.stalwart.networkListeners = desiredNetworkListeners;

  sops.secrets."stalwart/dns-task-api-key" = config.custom.mkSecret {
    owner = "stalwart";
    group = "stalwart";
    mode = "0400";
  };

  environment.etc."stalwart/config.json".source = datastoreBootstrap;

  systemd = {
    services.stalwart-dns-reconcile = {
      description = "Reconcile Stalwart-managed DNS records";
      wants = [
        "network-online.target"
        "sops-nix.service"
        "stalwart.service"
      ];
      after = [
        "network-online.target"
        "sops-nix.service"
        "stalwart.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "stalwart";
        Group = "stalwart";
        RuntimeDirectory = "stalwart-dns-reconcile";
        Environment = "HOME=/run/stalwart-dns-reconcile";
        ExecStart = "${dnsReconcile}/bin/stalwart-dns-reconcile";
        LoadCredential = [
          "api-key:${config.sops.secrets."stalwart/dns-task-api-key".path}"
        ];
      };
    };

    timers.stalwart-dns-reconcile = {
      description = "Daily Stalwart DNS reconciliation";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:15:00";
        Persistent = true;
        RandomizedDelaySec = "15m";
        Unit = "stalwart-dns-reconcile.service";
      };
    };

    tmpfiles.rules = [
      "d /etc/stalwart 0755 root root -"
      "d /etc/stalwart/certs 0755 root root -"
      "L+ /etc/stalwart/certs/${mailHost}_ecc/fullchain.cer - - - - /var/lib/acme/${mailHost}/fullchain.pem"
      "L+ /etc/stalwart/certs/${mailHost}_ecc/${mailHost}.key - - - - /var/lib/acme/${mailHost}/key.pem"
    ];

    # The upstream module owns this unit. Only replace its incompatible TOML
    # command and storage preparation with the existing 0.16 JSON bootstrap.
    services.stalwart = {
      unitConfig = {
        ConditionPathExists = lib.mkForce [
          "${dataDir}/database.sqlite"
          "/etc/stalwart/config.json"
        ];
        RequiresMountsFor = [ dataDir ];
      };
      serviceConfig = {
        ExecStartPre = lib.mkForce [ ];
        ExecStart = lib.mkForce [
          ""
          "${pkgs.stalwart_0_16}/bin/stalwart --config=/etc/stalwart/config.json"
        ];
      };
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "stalwart" with address "127.0.0.1"
      group mail
      group services
      if failed
        port ${toString (listenerPort "http")}
        protocol http
        with timeout 15 seconds
        for 3 cycles
      then alert

    ${mailPortChecksConfig}

    check program "stalwart-mail-health" with path "${mailHealthCheck}/bin/stalwart-mail-health ${mainDomain} ${dkimSelector}"
      group mail
      group services
      depends on "stalwart"
      # This aggregate probe opens several protocol sessions. Avoid creating
      a burst of local STARTTLS connections and tolerate transient refusals.
      every 2 cycles
      if status != 0 for 3 cycles then alert
  '';
}
