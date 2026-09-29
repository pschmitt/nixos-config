{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.hardware.nixosModules.raspberry-pi-4 ];

  hardware.raspberry-pi."4" = {
    bluetooth.enable = false;
    leds = {
      act.disable = true;
      eth.disable = true;
      pwr.disable = true;
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Enabling all hardware leads to build errors:
  # modprobe: FATAL: Module dw-hdmi not found in directory /nix/store/…
  hardware.enableAllHardware = lib.mkForce false;
  services.fwupd.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    raspberrypi-eeprom
  ];

  # flashrom (pulled in by raspberrypi-eeprom) fails its cmocka suite on
  # aarch64: write_chip_bad_status_test
  nixpkgs.overlays = [
    (_final: prev: {
      flashrom = prev.flashrom.overrideAttrs { doCheck = false; };
    })
  ];

  # Can't use btrfs storage driver!
  virtualisation.docker.storageDriver = lib.mkForce null;
}
