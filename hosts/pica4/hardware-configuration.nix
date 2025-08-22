{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hardware.nixosModules.raspberry-pi-4 ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

  # Enabling all hardware leads to build errors:
  # modprobe: FATAL: Module dw-hdmi not found in directory /nix/store/…
  hardware.enableAllHardware = lib.mkForce false;
  services.fwupd.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];
}
