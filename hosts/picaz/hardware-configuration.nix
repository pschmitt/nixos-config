{ lib, pkgs, ... }:
{
  # RPi Zero W — BCM2835, ARMv6
  nixpkgs.hostPlatform = lib.mkDefault "armv6l-linux";

  # sd-image-raspberrypi.nix pulls in nixos/modules/profiles/base.nix which adds
  # efibootmgr and efivar to systemPackages. Both are marked broken on armv6l
  # (no EFI on this platform). Stub them out so evaluation succeeds.
  nixpkgs.overlays = [
    (_final: prev: {
      efivar = prev.runCommand "efivar-stub" { } "mkdir $out";
      efibootmgr = prev.runCommand "efibootmgr-stub" { } "mkdir $out";
    })
  ];

  # Load the legacy V4L2 camera driver (requires start_x=1 + gpu_mem≥128 in config.txt)
  boot.kernelModules = [ "bcm2835-v4l2" ];

  # Trim things that either don't build on armv6l or are pointless on Zero W
  hardware.enableAllHardware = lib.mkForce false;
  services.fwupd.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;
}
