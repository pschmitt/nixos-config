{ configOptions, ... }:
{
  boot = {
    loader =
      if configOptions.useBIOS then {
        grub = {
          enable = true;
          configurationLimit = 10;
          # efiSupport = true;
        };
      } else {
        systemd-boot = {
          enable = true;
          configurationLimit = 10;
        };
        efi.canTouchEfiVariables = true;
      };
  };
}
