{ config, ... }:
{
  boot = {
    loader =
      if config.custom.raspberryPi then
        { }
      else if config.custom.useBIOS then
        {
          grub = {
            enable = true;
            configurationLimit = 10;
            # efiSupport = true;
          };
        }
      else
        {
          systemd-boot = {
            enable = true;
            configurationLimit = 10;
            netbootxyz.enable = true;
          };
          efi.canTouchEfiVariables = true;
        };
  };
}
