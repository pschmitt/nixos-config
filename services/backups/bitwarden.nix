{
  config,
  inputs,
  ...
}:

{
  imports = [
    inputs.bw-backup.nixosModules.default
  ];

  sops.secrets = {
    "bw-backup" = config.custom.mkSecret {
      owner = config.services.bw-backup.user;
      inherit (config.services.bw-backup) group;
    };
    "bw-sync" = config.custom.mkSecret {
      owner = config.services.bw-sync.user;
      inherit (config.services.bw-sync) group;
    };
  };

  services = {
    bw-backup = {
      enable = true;
      backupPath = "/srv/bw-backup/data";
      environmentFiles = [ config.sops.secrets."bw-backup".path ];
      retention = 30;
      monit = {
        enable = true;
        thresholdSeconds = 86400;
      };
    };

    bw-sync = {
      enable = true;
      purgeDestination = true;
      environmentFiles = [ config.sops.secrets."bw-sync".path ];
      monit = {
        enable = true;
        thresholdSeconds = 86400;
      };
    };
  };

  # A single hung `bw get attachment` download (no network timeout) can wedge
  # these oneshot units in "activating" forever, which also blocks the daily
  # timers. Fail instead so the next timer run retries and monit alerts.
  systemd.services = {
    bw-sync.serviceConfig.TimeoutStartSec = "2h";
    bw-backup.serviceConfig.TimeoutStartSec = "2h";
  };
}
