{
  inputs,
  lib,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    inputs.hardware.nixosModules.gpd-pocket-4
    ./disko-config.nix

    ../../hardware/fprintd.nix
    ../../hardware/touchscreen.nix
  ];

  swapDevices = [
    {
      device = "/swapfile";
      size = 16384; # storage space is basically free nowadays
    }
  ];

  networking.useDHCP = lib.mkDefault true;

  # ethernet nic, for network initrd
  boot.initrd.availableKernelModules = [ "r8169" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware = {
    highDpi = true;

    # Display rotation via IIO sensors
    sensor.iio.enable = lib.mkDefault true;
  };

  services.fprintd = {
    enable = true;
    package = pkgs.fprintd.override {
      libfprint = pkgs.libfprint-focaltech;
    };
  };

  environment.systemPackages = [

    (pkgs.writeShellApplication {
      name = "gpd-fanctl";
      runtimeInputs = [ pkgs.coreutils ];
      text = builtins.readFile ./scripts/gpd-fanctl.sh;
    })
  ];
}
