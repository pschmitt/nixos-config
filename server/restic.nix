{ config, lib, ... }: {
  services.restic.backups.main.paths = lib.mkForce [
    "/etc"
    "${config.custom.homeDirectory}"
  ];
}
