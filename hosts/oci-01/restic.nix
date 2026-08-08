{ lib, ... }:
{
  services.restic.backups.main.paths = lib.mkAfter [
    "/mnt/data/srv"
  ];
}
