{ config, pkgs, ... }:
{
  imports = [ ../../services/snapper.nix ];

  services.snapper = {
    snapshotRootOnBoot = false;
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    persistentTimer = true;

    configs.home = {
      FSTYPE = "btrfs";
      SUBVOLUME = "/home"; # @home won't work here
      ALLOW_USERS = [ config.mainUser.username ];
      TIMELINE_CREATE = true;
      TIMELINE_CLEANUP = true;
    };
  };

  environment.systemPackages = with pkgs; [ snapper-gui ];
}
