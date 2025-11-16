{ config, ... }:
{
  services.restic.backups.main.paths = [ config.users.users.mmonit.home ];
}
