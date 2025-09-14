{ lib, ... }:
{
  services.restic.backups.main.paths = lib.mkForce [ "/mnt/data/srv" ];
}
