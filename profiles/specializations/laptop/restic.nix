{ config, ... }:
{
  services.restic.backups.main.paths = [
    # bluetooth device data
    "/var/lib/bluetooth"
    # fingerprint data
    "/var/lib/fprint"

    # homedir
    "${config.mainUser.homeDirectory}/bin"
    "${config.mainUser.homeDirectory}/devel"
    "${config.mainUser.homeDirectory}/Documents"
    "${config.mainUser.homeDirectory}/Pictures"

    # config directories
    "${config.mainUser.homeDirectory}/.android" # adb
    "${config.mainUser.homeDirectory}/.config"
    "${config.mainUser.homeDirectory}/.var/app/com.obsproject.Studio/config/obs-studio"
  ];
}
