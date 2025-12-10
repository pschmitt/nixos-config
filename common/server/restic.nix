{ config, lib, ... }:
{
  imports = [ ../../services/restic ];

  config = lib.mkIf (!config.hardware.cattle) {
    services.restic.backups.main = {
      paths = [
        "/etc"
        "/var/lib"
        "${config.mainUser.homeDirectory}"
      ];
      exclude = [
        "/var/lib/docker"
        "/var/lib/cni"
        "/var/lib/containers"
        "/var/lib/flatpak"
        "/var/lib/systemd"
        "/var/lib/udisks"
      ];
    };
  };
}
