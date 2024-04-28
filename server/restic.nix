{ config, lib, ... }: {
  imports = [ ../common/restic ];

  services.restic.backups.main.paths = lib.mkForce [
    "/etc"
    "${config.custom.homeDirectory}"
  ];
}
