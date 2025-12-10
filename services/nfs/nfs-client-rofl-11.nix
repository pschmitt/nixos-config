{ config, ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-11.${config.domains.netbirdDomain}";
      exports = [ "videos" ];
      mountPoint = "/mnt/data";
    })
  ];
}
