{ lib, ... }:
{
  services.restic.backups.main.paths = lib.mkForce [ "/mnt/data/srv" ];
  services.restic.backups.main.exclude = [ "/mnt/data/srv/monerod/data" ];
}
