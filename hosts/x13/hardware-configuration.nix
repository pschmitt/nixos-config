{
  lib,
  inputs,
  modulesPath,
  ...
}:

{
  imports = [
    inputs.hardware.nixosModules.lenovo-thinkpad-x13-amd
    (modulesPath + "/installer/scan/not-detected.nix")
    ../../modules/disko/laptop-luks-btrfs.nix
    ../../profiles/hardware/fprintd.nix
  ];

  hardware.disko.laptop = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7HENU0Y622582M";
    espSize = "5120M";
  };

  # https://bugs.launchpad.net/ubuntu/+source/linux-source-2.6.17/+bug/76881
  boot.kernelParams = [ "i8042.probe_defer=1" ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "ehci_pci"
    "xhci_pci"
    "uas"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384; # storage space is basically free nowadays
    }
  ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
