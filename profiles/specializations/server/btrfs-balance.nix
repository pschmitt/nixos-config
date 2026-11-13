# Without a periodic balance, btrfs data chunks slowly consume all unallocated
# space. Metadata then cannot grow, and writes fail with ENOSPC while `df`
# still reports plenty of free space. rofl-12 hit this and could not finish the
# initrd activation (cpio: No space left on device) on any generation.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Subvolumes share one pool: balance each backing device once.
  btrfsMounts = lib.mapAttrsToList (_name: fs: fs.mountPoint) (
    lib.filterAttrs (_name: fs: fs.fsType == "btrfs") config.fileSystems
  );
  uniqueByDevice = lib.attrValues (
    lib.listToAttrs (
      lib.mapAttrsToList (_name: fs: lib.nameValuePair fs.device fs.mountPoint) (
        lib.filterAttrs (_name: fs: fs.fsType == "btrfs") config.fileSystems
      )
    )
  );
in
{
  config = lib.mkIf (btrfsMounts != [ ]) {
    systemd.services.btrfs-balance = {
      description = "Reclaim underused btrfs data chunks";
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
      script = lib.concatMapStringsSep "\n" (
        mnt:
        "${lib.getExe' pkgs.btrfs-progs "btrfs"} balance start -dusage=50 -musage=30 ${lib.escapeShellArg mnt}"
      ) uniqueByDevice;
    };

    systemd.timers.btrfs-balance = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 03:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };
}
