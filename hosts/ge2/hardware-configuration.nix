{
  config,
  inputs,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-pc-ssd
    ./fans.nix
    ../../misc/fprintd.nix

    # gpus
    ./intel-gpu.nix
    ./nvidia.nix
  ];

  boot = {
    kernelModules = [ "kvm-intel" ];
    extraModulePackages = [ ];
    initrd.availableKernelModules = [
      "nvme"
      "r8152" # wavlink dock nic
      "rtsx_pci_sdmmc"
      "sd_mod"
      "thunderbolt"
      "usb_storage"
      "xhci_pci"
    ];
  };

  # TODO remove below? These are already provided by disk-configuration.nix
  boot.initrd.luks.devices."encrypted".device =
    "/dev/disk/by-uuid/d4f522ea-e59a-4960-908d-dc8445e1ffcd";
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/23c2aab8-e91f-478f-a090-08ad0d604055";
      fsType = "btrfs";
      options = [ "subvol=@root" ];
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/1E3C-2DA0";
      fsType = "vfat";
    };

    "/home" = {
      device = "/dev/disk/by-uuid/23c2aab8-e91f-478f-a090-08ad0d604055";
      fsType = "btrfs";
      options = [ "subvol=@home" ];
    };

    "/nix" = {
      device = "/dev/disk/by-uuid/23c2aab8-e91f-478f-a090-08ad0d604055";
      fsType = "btrfs";
      options = [ "subvol=@nix" ];
    };
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # TODO remove this? This might already be provided by the nixos-hardware modules
  powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  services.thermald.enable = true; # intel only

  # FIXME MIPI Camera
  # hardware.ipu6 = {
  #   enable = true;
  #   # NOTE ipu6ep is for Raptor Lake
  #   platform = "ipu6ep";
  # };

}
