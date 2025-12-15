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
    "bw-backup" = {
      inherit (config.custom) sopsFile;
      owner = config.services.bw-backup.user;
      inherit (config.services.bw-backup) group;
    };
    "bw-sync" = {
      inherit (config.custom) sopsFile;
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
}
