{ configOptions, ... }:
{
  boot = {
    loader =
      if configOptions.useBIOS then {
        grub = {
          enable = true;
          efiSupport = true;
        };
      } else {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
  };
}
