{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hardware.nixosModules.raspberry-pi-4 ];

  hardware = {
    i2c.enable = true;

    raspberry-pi."4" = {
      bluetooth.enable = true;
    #   i2c0.enable = false;
    #   i2c1.enable = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

  # Enabling all hardware leads to build errors:
  # modprobe: FATAL: Module dw-hdmi not found in directory /nix/store/…
  hardware.enableAllHardware = lib.mkForce false;
  services.fwupd.enable = lib.mkForce false;

  # mount the fw partition as /boot/firmware
  # FIXME This fails to activate:
  # Error: Failed to open unit file /nix/store/br5yy8zkrwrlk6rvsxv1j68d5klkxh4s-nixos-system-pica4-sd-card-25.11.20250819.2007595/etc/systemd/system/boot-firmware.mount
  # Caused by:
  #     No such file or directory (os error 2)
  # fileSystems."/boot/firmware" = {
  #   device = "/dev/disk/by-label/FIRMWARE";
  #   fsType = "vfat";
  #   options = lib.mkForce [
  #     "auto"
  #     "nofail"
  #     # root-only by default
  #     "fmask=0077"
  #     "dmask=0077"
  #   ];
  # };

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  # Can't use btrfs storage driver!
  virtualisation.docker.storageDriver = lib.mkForce null;
}
