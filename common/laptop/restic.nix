{ config, ... }:
{
  services.restic.backups.main.paths = [
    # bluetooth device data
    "/var/lib/bluetooth"
    # fingerprint data
    "/var/lib/fprint"

    # homedir
    "${config.custom.homeDirectory}/bin"
    "${config.custom.homeDirectory}/devel"
    "${config.custom.homeDirectory}/Documents"
    "${config.custom.homeDirectory}/Pictures"

    # config directories
    "${config.custom.homeDirectory}/.android" # adb
    "${config.custom.homeDirectory}/.config"
    "${config.custom.homeDirectory}/.var/app/com.obsproject.Studio/config/obs-studio"
  ];
}
