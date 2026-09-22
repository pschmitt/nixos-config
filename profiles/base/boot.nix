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
    kernelPackages = lib.mkDefault (
      if config.hardware.type == "rpi" then
        pkgs.linuxKernel.packages.linux_rpi4
      else
        pkgs.linuxPackages_latest
    );
    tmp = {
      useTmpfs = true;
    };
  };
}
