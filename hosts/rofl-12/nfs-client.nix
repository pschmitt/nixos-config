{ config, ... }:
{
  imports = [ ../../services/nfs/nfs-client.nix ];

  services.nfsMounts = {
    enable = true;
    server = "rofl-10.${config.domains.vpn}";
  };
}
