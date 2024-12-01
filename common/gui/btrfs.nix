{
  pkgs,
  ...
}:
{
  services.snapper = {
    snapshotRootOnBoot = false;
    snapshotInterval = "hourly";
    cleanupInterval = "1d";

    configs = {
      home = {
        FSTYPE = "btrfs";
        # NOTE make sure that there is a .snapshots subvolume!
        # sudo btrfs subvolume create /home/.snapshots
        SUBVOLUME = "/home"; # @home won't work here
        ALLOW_USERS = [ "pschmitt" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [ snapper-gui ];
}
