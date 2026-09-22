{ lib, ... }:
{
  boot.kernelParams = [ "ip=dhcp" ];

  boot.initrd = {
    network.enable = lib.mkForce true;
  };
}
