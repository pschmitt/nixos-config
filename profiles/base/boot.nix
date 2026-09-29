{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot = {
    kernel.sysctl = {
      # Enable all MagicSysRq keys
      "kernel.sysrq" = 1;
    };
    # RPi hosts get their downstream kernel from nixos-hardware
    kernelPackages = lib.mkIf (config.hardware.type != "rpi") (lib.mkDefault pkgs.linuxPackages_latest);
    tmp = {
      useTmpfs = true;
    };
  };
}
