{ lib, pkgs, ... }:
{
  # RPi Zero W — BCM2835, ARMv6
  nixpkgs.hostPlatform = lib.mkDefault "armv6l-linux";

  # sd-image-raspberrypi.nix already sets linux_rpi1; mkForce guards against
  # any profile importing profiles/global/boot.nix which uses linux_rpi4 as mkDefault.
  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi1;

  # Load the legacy V4L2 camera driver (requires start_x=1 + gpu_mem≥128 in config.txt)
  boot.kernelModules = [ "bcm2835-v4l2" ];

  # Trim things that either don't build on armv6l or are pointless on Zero W
  hardware.enableAllHardware = lib.mkForce false;
  services.fwupd.enable = lib.mkForce false;
}
