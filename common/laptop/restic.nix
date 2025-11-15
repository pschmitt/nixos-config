{ config, lib, ... }:
{
  services.restic.backups.main.paths = lib.mkAfter [
    # bluetooth device data
    "/var/lib/bluetooth"

    # homedir
    "${config.custom.homeDirectory}/devel"
    "${config.custom.homeDirectory}/Documents"
    "${config.custom.homeDirectory}/Pictures"
    "${config.custom.homeDirectory}/.config"
    "${config.custom.homeDirectory}/.var/app/com.obsproject.Studio/config/obs-studio"
  ];
}
