{ ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-08.netbird.cloud";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
