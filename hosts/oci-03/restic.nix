{ lib, ... }:
{
  services.restic.backups.main.paths = lib.mkForce [ "/var/lib/mmonit" ];
}
