{ config, ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-11.${config.domains.netbird}";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
