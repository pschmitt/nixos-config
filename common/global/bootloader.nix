{ configOptions, ... }:
{
  boot = {
    loader =
      if configOptions.useBIOS then {
        grub = {
          enable = true;
          enableCryptodisk = true;
          # efiSupport = true;
          # FIXME Should we set this?!
          # device = "nodev";
        };
      } else {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
  };
}
