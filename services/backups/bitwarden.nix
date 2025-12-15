{
  config,
  inputs,
  ...
}:

{
  imports = [
    inputs.bw-backup.nixosModules.default
  ];

  sops.secrets."bw-backup" = {
    inherit (config.custom) sopsFile;
    owner = "bw-backup";
    group = "bw-backup";
  };

  bw-backup = {
    backup = {
      enable = true;
      backupPath = "/srv/bw-backup/data";
      environmentFiles = [ config.sops.secrets."bw-backup".path ];
      retention = 30;
    };
    monit = {
      enable = true;
      thresholdSeconds = 86400;
    };
  };
}
