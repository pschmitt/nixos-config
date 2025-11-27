{ config, lib, ... }:
{
  imports = [ ../common/restic ];

  config = lib.mkIf (!config.custom.cattle) {
    services.restic.backups.main = {
      paths = [
        "/etc"
        "/var/lib"
        "${config.custom.homeDirectory}"
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
