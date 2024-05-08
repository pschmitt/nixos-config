{ config, lib, ... }: {
  imports = [ ../common/restic ];

  config = lib.mkIf (!config.custom.cattle) {
    services.restic.backups.main.paths = lib.mkForce [
      "/etc"
      "${config.custom.homeDirectory}"
    ];
  };
}
