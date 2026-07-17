{ ... }:
{
  imports = [
    ./nfs-client.nix
  ];

  services.nfsMounts.enable = true;
}
