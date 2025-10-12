{
  config,
  lib,
  pkgs,
  ...
}:
let
  createSnapshotsSubvolume = pkgs.writeShellScript "snapper-create-snapshots-subvolume" ''
    if ${pkgs.btrfs-progs}/bin/btrfs subvolume show /home/.snapshots
    then
      echo "/home/.snapshots already exits, nothing to do."
      exit 0
    fi

    echo "Creating /home/.snapshots subvolume for snapper..."
    ${pkgs.btrfs-progs}/bin/btrfs subvolume create /home/.snapshots
  '';
in
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
        ALLOW_USERS = [ config.custom.username ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [ snapper-gui ];

  systemd.services.snapperd.serviceConfig.ExecStartPre = lib.mkBefore [
    createSnapshotsSubvolume
  ];
}
