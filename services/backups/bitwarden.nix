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
    backupPath = "/srv/bw-backup";
    backup.enable = true;
    backup.environmentFiles = [ config.sops.secrets."bw-backup".path ];
    monit.enable = true;
    monit.thresholdSeconds = 86400;
  };
}
