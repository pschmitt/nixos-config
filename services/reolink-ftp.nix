{
  config,
  pkgs,
  ...
}:
let
  reolinkDataDir = "/mnt/sda1/reolink";
  certsDir = "/srv/ftp/config/certs";
in
{
  sops.secrets."ftp/reolink/password" = config.custom.mkSecret { };

  sops.templates."pure-ftpd.env".content = ''
    PUBLICHOST=10.5.0.15
    FTP_PASSIVE_PORTS=30000:30009
    FTP_USER_NAME=reolink
    FTP_USER_PASS=${config.sops.placeholder."ftp/reolink/password"}
    FTP_USER_HOME=/data
  '';

  virtualisation.oci-containers.containers.ftpd = {
    image = "stilliard/pure-ftpd:latest";
    autoStart = true;
    environmentFiles = [
      config.sops.templates."pure-ftpd.env".path
    ];
    ports = [
      "21:21"
      "990:990"
      "30000-30009:30000-30009"
    ];
    volumes = [
      "${reolinkDataDir}:/data"
      "${certsDir}:/etc/ssl/private:ro"
    ];
  };

  # Native systemd prune timer replacing the alpine cron container
  systemd.services.reolink-prune = {
    description = "Prune Reolink camera footage older than 7 days";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "reolink-prune" ''
        ${pkgs.findutils}/bin/find ${reolinkDataDir} -type f -mmin +10080 -print -delete
        ${pkgs.findutils}/bin/find ${reolinkDataDir} -mindepth 1 -type d -empty -delete
      '';
    };
  };

  systemd.timers.reolink-prune = {
    description = "Prune Reolink camera footage periodically";
    timerConfig = {
      OnCalendar = "*:0/10";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
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
