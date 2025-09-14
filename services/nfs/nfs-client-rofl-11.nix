{ config, ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-11.nb.${config.custom.mainDomain}";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
