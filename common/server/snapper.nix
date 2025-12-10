{ config, lib, ... }:
let
  dataDir = "/mnt/data";
  dataFileSystem = lib.attrByPath [ dataDir ] { } config.fileSystems;
  dataIsBtrfs = (dataFileSystem.fsType or null) == "btrfs";
in
{
  imports = [ ../../services/snapper.nix ];

  services.snapper = {
    snapshotRootOnBoot = lib.mkDefault false;
    snapshotInterval = lib.mkDefault "hourly";
    cleanupInterval = lib.mkDefault "1d";
    persistentTimer = lib.mkDefault true;

    configs = lib.mkIf dataIsBtrfs {
      data = lib.mkDefault {
        FSTYPE = "btrfs";
        SUBVOLUME = dataDir;
        ALLOW_USERS = [ config.mainUser.username ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };
}
