{ config, ... }:
{
  boot = {
    loader =
      if config.hardware.type == "rpi" then
        { }
      else if config.hardware.biosBoot then
        {
          grub = {
            enable = true;
            configurationLimit = 10;
            efiSupport = true;
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
