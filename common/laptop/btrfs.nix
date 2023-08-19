{ inputs, lib, config, pkgs, ... }: {
  services.snapper = {
    snapshotRootOnBoot = false;
    snapshotInterval = "1h";
    cleanupInterval = "1d";

    configs = {
      home = {
        FSTYPE = "btrfs";
        SUBVOLUME = "/home";
        ALLOW_USERS = [ "pschmitt" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [
    snapper-gui
  ];
}
