{ config, lib, ... }:
{
  options.hardware.rpi.kernelPackages = lib.mkOption {
    type = lib.types.attrs;
    description = "The downstream Linux kernel package set for this Raspberry Pi model.";
  };

  config.boot.kernelPackages = lib.mkForce config.hardware.rpi.kernelPackages;
}
