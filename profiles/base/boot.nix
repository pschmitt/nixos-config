{
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
    # Keep this as a fallback so hardware profiles and specializations can
    # select their own kernel packages.
    kernelPackages = lib.mkOverride 1100 pkgs.linuxPackages_latest;
    tmp = {
      cleanOnBoot = lib.mkDefault true;
    };
  };
}
