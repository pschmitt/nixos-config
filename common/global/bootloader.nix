{ configOptions, ... }:
{
  boot = {
    loader =
      if configOptions.useBIOS then {
        grub = {
          enable = true;
          # efiSupport = true;
          device = "nodev";
        };
      } else {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
  };
}
