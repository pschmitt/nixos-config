{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hardware.nixosModules.raspberry-pi-4 ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot = {
    kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

    # Including the default modules leads to build errors:
    # modprobe: FATAL: Module dw-hdmi not found in directory /nix/store/…
    initrd.availableKernelModules = lib.mkForce [
      "usbhid"
      "usb_storage"
      "vc4"
      "pcie_brcmstb" # required for the pcie bus to work
      "reset-raspberrypi" # required for vl805 firmware to load
    ];
    # initrd.includeDefaultModules = false;
    # initrd.kernelModules = lib.mkForce [ ];
  };

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];
}
