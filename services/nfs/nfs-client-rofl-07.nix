{ ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-07.netbird.cloud";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
