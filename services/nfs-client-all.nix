{ ... }:
{
  imports = [
    # rofl-02
    (import ./nfs-client.nix { })

    # rofl-07
    (import ./nfs-client.nix {
      server = "rofl-07.netbird.cloud";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
