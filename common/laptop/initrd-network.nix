{ lib, ... }:
{
  boot.kernelParams = [ "ip=dhcp" ];

  boot.initrd = {
    # availableKernelModules = [
    #   "r8152"
    #   "r8169"
    # ];
    network.enable = lib.mkForce true;
  };
}
