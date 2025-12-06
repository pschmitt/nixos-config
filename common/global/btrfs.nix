{
  config,
  lib,
  ...
}:
let
  hasBtrfsFs = lib.any (fs: fs.fsType == "btrfs") (builtins.attrValues config.fileSystems);
in
{
  config = lib.mkIf hasBtrfsFs {
    services.btrfs.autoScrub = {
      enable = true;
      # fileSystems = [ "/" ]; # default is all btrfs file systems
      limit = "100M"; # max throughput
    };
  };
}
