{
  config,
  pkgs,
  ...
}:
let
  reolinkDataDir = "/mnt/sda1/reolink";
  certsDir = "/srv/ftp/config/certs";
  # Nixpkgs enables TLS but does not enable the container's PureDB backend.
  pureFtpd = pkgs.pure-ftpd.overrideAttrs (old: {
    configureFlags = old.configureFlags ++ [ "--with-puredb" ];
  });
  prepareUsers = pkgs.writeShellApplication {
    name = "reolink-ftp-users";
    runtimeInputs = [
      pureFtpd
      pkgs.coreutils
    ];
    text = builtins.readFile ./scripts/reolink-ftp-users.sh;
  };
in
{
  sops.secrets."ftp/reolink/password" = config.custom.mkSecret { };

  systemd = {
    services = {
      ftpd = {
        description = "Native Pure-FTPd for Reolink camera uploads";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        unitConfig.RequiresMountsFor = [
          reolinkDataDir
          certsDir
        ];
        bindsTo = [ "mnt-sda1.mount" ];
        environment.REOLINK_DATA_DIR = reolinkDataDir;
        serviceConfig = {
          Type = "simple";
          RuntimeDirectory = "reolink-ftp";
          RuntimeDirectoryMode = "0700";
          LoadCredential = [ "password:${config.sops.secrets."ftp/reolink/password".path}" ];
          ExecStartPre = "${prepareUsers}/bin/reolink-ftp-users";
          # No forced passive address: advertise the local connection address on lrz,
          # rather than fnuc's production address. PureDB is the only auth backend.
          # Port 990 was published by Docker but had no implicit-TLS listener.
          ExecStart = "${pureFtpd}/bin/pure-ftpd -l puredb:/run/reolink-ftp/pureftpd.pdb -E -j -R -p 30000:30009 -c 5 -C 5 --tls=1 --certfile=${certsDir}/pure-ftpd.pem";
          Restart = "on-failure";
          RestartSec = "5s";
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ reolinkDataDir ];
        };
      };

      # Native systemd prune timer replacing the alpine cron container
      reolink-prune = {
        description = "Prune Reolink camera footage older than 7 days";
        unitConfig.RequiresMountsFor = [ reolinkDataDir ];
        bindsTo = [ "mnt-sda1.mount" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "reolink-prune" ''
            ${pkgs.coreutils}/bin/timeout 5m ${pkgs.findutils}/bin/find ${reolinkDataDir} -xdev -type f -mmin +10080 -print -delete
            ${pkgs.coreutils}/bin/timeout 5m ${pkgs.findutils}/bin/find ${reolinkDataDir} -xdev -mindepth 1 -type d -empty -delete
          '';
        };
      };
    };

    timers.reolink-prune = {
      description = "Prune Reolink camera footage periodically";
      timerConfig = {
        OnCalendar = "*:0/10";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      21
      990
    ];
    allowedTCPPortRanges = [
      {
        from = 30000;
        to = 30009;
      }
    ];
  };
}
