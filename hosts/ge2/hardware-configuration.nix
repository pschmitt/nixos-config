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
    ./disko-config.nix
    ./fans.nix
    ../../hardware/fprintd.nix

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
