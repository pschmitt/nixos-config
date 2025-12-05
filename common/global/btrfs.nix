{
  services.btrfs.autoScrub = {
    enable = true;
    # fileSystems = [ "/" ]; # default is all btrfs file systems
    limit = "100M"; # max throughput
  };
}
