{ config, lib, ... }:
{
  imports = [ ../services/snapper.nix ];

  services.snapper = {
    snapshotRootOnBoot = lib.mkDefault false;
    snapshotInterval = lib.mkDefault "hourly";
    cleanupInterval = lib.mkDefault "1d";
    persistentTimer = lib.mkDefault true;

    configs.srv = lib.mkDefault {
      FSTYPE = "btrfs";
      SUBVOLUME = "/srv";
      ALLOW_USERS = [ config.custom.username ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
    };
  };
}
